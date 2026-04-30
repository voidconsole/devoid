const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const morgan = require('morgan');
const cors = require('cors');
const nacl = require('tweetnacl');
const { v4: uuidv4 } = require('uuid');
const Database = require('better-sqlite3');
const crypto = require('crypto');
const WebSocket = require('ws');
const http = require('http');
const path = require('path');
const fs = require('fs');

// Initialize Express
const app = express();
const PORT = 9000;

// Create HTTP server
const server = http.createServer(app);

// Initialize WebSocket server
const wss = new WebSocket.Server({ server });

// Track connected clients: { publicKey: WebSocket }
const connectedClients = new Map();

// Trust ONLY nginx proxy (localhost)
app.set('trust proxy', 'loopback');

// Initialize SQLite Database
const db = new Database('devoid.db');
db.pragma('journal_mode = WAL');

// ============================================================================
// HUB ACCESS CONTROL
// ============================================================================

const HUBS_FILE_PATH = path.join(__dirname, 'hubs.json');
let hubsConfig = { hubs: [] };

function loadHubs() {
        try {
                if (!fs.existsSync(HUBS_FILE_PATH)) {
                        console.warn('⚠️  hubs.json not found — open mode (all registered users can reach each other)');
                        hubsConfig = { hubs: [] };
                        return;
                }

                const raw = fs.readFileSync(HUBS_FILE_PATH, 'utf8');
                const parsed = JSON.parse(raw);
                hubsConfig = parsed;

                console.log(`✓ Loaded ${hubsConfig.hubs.length} hub(s) from hubs.json`);
                hubsConfig.hubs.forEach(h => {
                        console.log(`  Hub "${h.name}": [${h.members.join(', ')}]`);
                });
        } catch (err) {
                console.error('❌ Failed to load hubs.json (keeping previous config):', err.message);
        }
}

loadHubs();

// Hot-reload hubs every 5 seconds without restarting the server
fs.watchFile(HUBS_FILE_PATH, { interval: 5000 }, (curr, prev) => {
        if (curr.mtime !== prev.mtime) {
                console.log('🔄 hubs.json changed, reloading...');
                loadHubs();
        }
});

/**
 * Returns a Set of usernames reachable from the given username.
 * Returns null if in open mode (no hubs configured) — meaning all users reachable.
 * A user can always reach themselves (excluded from the returned set).
 */
function getReachableUsernames(username) {
        if (hubsConfig.hubs.length === 0) {
                return null; // Open mode
        }

        const reachable = new Set();

        for (const hub of hubsConfig.hubs) {
                if (hub.members.includes(username)) {
                        hub.members.forEach(m => {
                                if (m !== username) reachable.add(m);
                        });
                }
        }

        return reachable;
}

/**
 * Returns true if pubKeyA is allowed to send messages to pubKeyB.
 * Checks hub membership using their registered usernames.
 */
function canPublicKeysConnect(pubKeyA, pubKeyB) {
        if (pubKeyA === pubKeyB) return false;

        // Open mode — no restriction
        if (hubsConfig.hubs.length === 0) return true;

        const userA = db.prepare('SELECT username FROM users WHERE public_key = ?').get(pubKeyA);
        const userB = db.prepare('SELECT username FROM users WHERE public_key = ?').get(pubKeyB);

        if (!userA || !userB) return false;

        const reachable = getReachableUsernames(userA.username);

        if (reachable === null) return true; // Open mode

        return reachable.has(userB.username);
}

// ============================================================================
// SECURITY MIDDLEWARE
// ============================================================================

app.use(helmet({
        contentSecurityPolicy: false,
}));

app.use(cors({
        origin: '*',
        methods: ['GET', 'POST'],
}));

app.use(morgan('combined'));

// Increased to 50mb to support encrypted media (base64 adds ~33% overhead)
app.use(express.json({ limit: '50mb' }));
app.use(express.raw({ type: 'application/octet-stream', limit: '50mb' }));

// URL-decode middleware
app.use((req, res, next) => {
        if (req.params.publicKey) {
                req.params.publicKey = decodeURIComponent(req.params.publicKey);
        }
        next();
});

// Rate limiting
const authLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 10,
        message: 'Too many authentication attempts',
        standardHeaders: true,
        legacyHeaders: false,
        validate: { trustProxy: false },
});

const messageLimiter = rateLimit({
        windowMs: 1 * 60 * 1000,
        max: 60,
        message: 'Rate limit exceeded',
        validate: { trustProxy: false },
});

// ============================================================================
// WEBSOCKET HANDLING
// ============================================================================

wss.on('connection', (ws) => {
        console.log('🔌 New WebSocket connection');

        let userPublicKey = null;

        ws.on('message', (message) => {
                try {
                        const data = JSON.parse(message.toString());

                        if (data.type === 'auth') {
                                const { publicKey } = data;
                                const user = db.prepare('SELECT * FROM users WHERE public_key = ?').get(publicKey);

                                if (user) {
                                        userPublicKey = publicKey;
                                        connectedClients.set(publicKey, ws);

                                        console.log(`✓ WebSocket authenticated: ${publicKey.substring(0, 12)}...`);
                                        console.log(`  Total connected clients: ${connectedClients.size}`);

                                        ws.send(JSON.stringify({
                                                type: 'auth_success',
                                                message: 'WebSocket authenticated'
                                        }));

                                        sendPendingMessages(publicKey);
                                } else {
                                        ws.send(JSON.stringify({
                                                type: 'auth_failed',
                                                message: 'User not found'
                                        }));
                                        ws.close();
                                }
                        }

                        if (data.type === 'ping') {
                                ws.send(JSON.stringify({ type: 'pong' }));
                        }
                } catch (error) {
                        console.error('WebSocket message error:', error);
                }
        });

        ws.on('close', () => {
                if (userPublicKey) {
                        connectedClients.delete(userPublicKey);
                        console.log(`🔌 WebSocket disconnected: ${userPublicKey.substring(0, 12)}...`);
                        console.log(`  Total connected clients: ${connectedClients.size}`);
                }
        });

        ws.on('error', (error) => {
                console.error('WebSocket error:', error);
        });
});

/**
 * Send pending undelivered messages to a user who just connected.
 */
function sendPendingMessages(publicKey) {
        try {
                const messages = db.prepare(`
                        SELECT
                                m.id as messageId,
                                m.from_key as "from",
                                m.encrypted_content as encrypted,
                                m.timestamp,
                                m.type,
                                m.file_name as fileName,
                                m.mime_type as mimeType,
                                u.username as fromUsername
                        FROM messages m
                        LEFT JOIN users u ON m.from_key = u.public_key
                        WHERE m.to_key = ? AND m.delivered = 0
                        ORDER BY m.created_at ASC
                `).all(publicKey);

                if (messages.length > 0) {
                        const ws = connectedClients.get(publicKey);
                        if (ws && ws.readyState === WebSocket.OPEN) {
                                console.log(`📬 Sending ${messages.length} pending message(s) to ${publicKey.substring(0, 12)}...`);

                                messages.forEach(msg => {
                                        ws.send(JSON.stringify({
                                                type: 'new_message',
                                                message: msg
                                        }));
                                        db.prepare('UPDATE messages SET delivered = 1 WHERE id = ?').run(msg.messageId);
                                });
                        }
                }
        } catch (error) {
                console.error('Error sending pending messages:', error);
        }
}

/**
 * Push a message to a recipient via WebSocket if they're online.
 */
function pushMessageToRecipient(recipientPublicKey, message) {
        const ws = connectedClients.get(recipientPublicKey);

        if (ws && ws.readyState === WebSocket.OPEN) {
                console.log(`📨 Pushing message to ${recipientPublicKey.substring(0, 12)}... (online)`);

                ws.send(JSON.stringify({
                        type: 'new_message',
                        message: message
                }));

                db.prepare('UPDATE messages SET delivered = 1 WHERE id = ?').run(message.messageId);

                return true;
        } else {
                console.log(`📭 Recipient ${recipientPublicKey.substring(0, 12)}... offline, will deliver later`);
                return false;
        }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

function verifySignature(publicKeyBase64, messageBase64, signatureBase64) {
        try {
                const publicKey = Buffer.from(publicKeyBase64, 'base64');
                const message = Buffer.from(messageBase64, 'base64');
                const signature = Buffer.from(signatureBase64, 'base64');

                if (publicKey.length !== 32 || signature.length !== 64) {
                        return false;
                }

                return nacl.sign.detached.verify(message, signature, publicKey);
        } catch (error) {
                console.error('Signature verification error:', error);
                return false;
        }
}

function generateChallenge() {
        return crypto.randomBytes(32).toString('base64');
}

function cleanupExpiredData() {
        const now = Date.now();

        db.prepare('DELETE FROM challenges WHERE created_at < ?')
                .run(now - 5 * 60 * 1000);

        db.prepare('DELETE FROM sessions WHERE created_at < ?')
                .run(now - 24 * 60 * 60 * 1000);

        // Delete delivered messages older than 7 days
        db.prepare('DELETE FROM messages WHERE created_at < ? AND delivered = 1')
                .run(now - 7 * 24 * 60 * 60 * 1000);

        console.log('Cleanup completed at', new Date().toISOString());
}

setInterval(cleanupExpiredData, 60 * 60 * 1000);

// ============================================================================
// API ENDPOINTS
// ============================================================================

app.get('/health', (req, res) => {
        res.json({
                status: 'ok',
                timestamp: new Date().toISOString(),
                uptime: process.uptime(),
                connectedClients: connectedClients.size
        });
});

app.get('/welcome', (req, res) => {
        res.sendFile(path.join(__dirname, 'site/welcome.html'));
});

app.get('/auth/challenge', authLimiter, (req, res) => {
        try {
                const challenge = generateChallenge();
                const challengeId = uuidv4();
                const now = Date.now();

                db.prepare(`
                        INSERT INTO challenges (id, challenge, created_at)
                        VALUES (?, ?, ?)
                `).run(challengeId, challenge, now);

                res.json({ challengeId, challenge });
        } catch (error) {
                console.error('Challenge generation error:', error);
                res.status(500).json({ error: 'Failed to generate challenge' });
        }
});

app.post('/auth/verify', authLimiter, (req, res) => {
        try {
                const { publicKey, signature, challenge, encryptionPublicKey } = req.body;

                if (!publicKey || !signature || !challenge) {
                        return res.status(400).json({ error: 'Missing required fields' });
                }

                const challengeRecord = db.prepare(`
                        SELECT * FROM challenges
                        WHERE challenge = ? AND created_at > ?
                `).get(challenge, Date.now() - 5 * 60 * 1000);

                if (!challengeRecord) {
                        return res.status(401).json({
                                verified: false,
                                error: 'Invalid or expired challenge'
                        });
                }

                const isValid = verifySignature(publicKey, challenge, signature);
                if (!isValid) {
                        return res.status(401).json({
                                verified: false,
                                error: 'Invalid signature'
                        });
                }

                const allowedUser = db.prepare('SELECT * FROM users WHERE public_key = ?').get(publicKey);
                if (!allowedUser) {
                        console.log(`Unauthorized auth attempt: ${publicKey.substring(0, 20)}...`);
                        return res.status(403).json({
                                verified: false,
                                error: 'User not authorized. Contact admin for access.'
                        });
                }

                db.prepare('DELETE FROM challenges WHERE challenge = ?').run(challenge);

                const token = crypto.randomBytes(32).toString('base64');

                if (encryptionPublicKey) {
                        db.prepare(`
                                UPDATE users
                                SET encryption_public_key = ?, last_seen = ?
                                WHERE public_key = ?
                        `).run(encryptionPublicKey, Date.now(), publicKey);
                } else {
                        db.prepare(`
                                UPDATE users SET last_seen = ? WHERE public_key = ?
                        `).run(Date.now(), publicKey);
                }

                console.log(`User authenticated: ${publicKey.substring(0, 10)}...`);
                res.json({ verified: true, token, publicKey });
        } catch (error) {
                console.error('Auth error:', error);
                res.status(500).json({ error: 'Verification failed' });
        }
});

app.post('/session/start', authLimiter, (req, res) => {
        try {
                const { userPublicKey, clientEphemeralPublicKey } = req.body;

                if (!userPublicKey || !clientEphemeralPublicKey) {
                        return res.status(400).json({ error: 'Missing required fields' });
                }

                const user = db.prepare('SELECT * FROM users WHERE public_key = ?').get(userPublicKey);

                if (!user) {
                        return res.status(401).json({ error: 'User not authenticated' });
                }

                const serverEphemeralPublicKey = crypto.randomBytes(32).toString('base64');
                const sessionId = uuidv4();
                const salt = crypto.randomBytes(16).toString('base64');

                db.prepare(`
                        INSERT INTO sessions (
                                id, user_public_key, client_ephemeral_key,
                                server_ephemeral_key, salt, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?)
                `).run(sessionId, userPublicKey, clientEphemeralPublicKey, serverEphemeralPublicKey, salt, Date.now());

                res.json({ sessionId, serverEphemeralPublicKey, salt });
        } catch (error) {
                console.error('Session start error:', error);
                res.status(500).json({ error: 'Failed to start session' });
        }
});

app.post('/session/end', (req, res) => {
        try {
                const { sessionId } = req.body;

                if (sessionId) {
                        db.prepare('DELETE FROM sessions WHERE id = ?').run(sessionId);
                }

                res.json({ success: true });
        } catch (error) {
                console.error('Session end error:', error);
                res.status(500).json({ error: 'Failed to end session' });
        }
});

app.post('/send', messageLimiter, (req, res) => {
        try {
                const { from, to, encrypted, timestamp, sessionId, type, fileName, mimeType } = req.body;

                if (!from || !to || !encrypted) {
                        return res.status(400).json({ error: 'Missing required fields' });
                }

                const sender = db.prepare('SELECT * FROM users WHERE public_key = ?').get(from);
                if (!sender) {
                        return res.status(401).json({ error: 'Sender not authenticated' });
                }

                const recipient = db.prepare('SELECT * FROM users WHERE public_key = ?').get(to);
                if (!recipient) {
                        return res.status(404).json({ error: 'Recipient not found' });
                }

                // Hub connectivity check — enforced for both text and media
                if (!canPublicKeysConnect(from, to)) {
                        console.warn(`🚫 Hub violation: ${sender.username} → ${recipient.username}`);
                        return res.status(403).json({ error: 'Messaging not permitted between these users' });
                }

                const messageId = uuidv4();

                db.prepare(`
                        INSERT INTO messages (
                                id, from_key, to_key, encrypted_content,
                                timestamp, session_id, created_at, type, file_name, mime_type, delivered
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                `).run(
                        messageId, from, to, encrypted,
                        timestamp || new Date().toISOString(),
                        sessionId, Date.now(),
                        type || 'text', fileName || null, mimeType || null
                );

                console.log(`Message routed: ${from.substring(0, 8)}... → ${to.substring(0, 8)}... [${type || 'text'}]`);

                const messageObj = {
                        messageId,
                        from,
                        encrypted,
                        timestamp: timestamp || new Date().toISOString(),
                        type: type || 'text',
                        fileName: fileName || null,
                        mimeType: mimeType || null,
                        fromUsername: sender.username
                };

                const pushed = pushMessageToRecipient(to, messageObj);

                res.json({
                        messageId,
                        success: true,
                        delivered: pushed
                });
        } catch (error) {
                console.error('Send message error:', error);
                res.status(500).json({ error: 'Failed to send message' });
        }
});

// Polling fallback for undelivered messages
app.get('/recv/:publicKey', messageLimiter, (req, res) => {
        try {
                const { publicKey } = req.params;

                const user = db.prepare('SELECT * FROM users WHERE public_key = ?').get(publicKey);
                if (!user) {
                        return res.status(401).json({ error: 'User not authenticated' });
                }

                const messages = db.prepare(`
                        SELECT
                                m.id as messageId,
                                m.from_key as "from",
                                m.encrypted_content as encrypted,
                                m.timestamp,
                                m.type,
                                m.file_name as fileName,
                                m.mime_type as mimeType,
                                u.username as fromUsername
                        FROM messages m
                        LEFT JOIN users u ON m.from_key = u.public_key
                        WHERE m.to_key = ? AND m.delivered = 0
                        ORDER BY m.created_at ASC
                        LIMIT 100
                `).all(publicKey);

                if (messages.length > 0) {
                        const messageIds = messages.map(m => m.messageId);
                        const placeholders = messageIds.map(() => '?').join(',');
                        db.prepare(`UPDATE messages SET delivered = 1 WHERE id IN (${placeholders})`).run(...messageIds);
                }

                res.json({ messages });
        } catch (error) {
                console.error('Receive messages error:', error);
                res.status(500).json({ error: 'Failed to receive messages' });
        }
});

app.get('/conversation/:publicKey', messageLimiter, (req, res) => {
        try {
                const { publicKey } = req.params;
                const { other, limit = 50 } = req.query;

                if (!other) {
                        return res.status(400).json({ error: 'Missing other user public key' });
                }

                const otherPublicKey = decodeURIComponent(other);

                const user = db.prepare('SELECT * FROM users WHERE public_key = ?').get(publicKey);
                if (!user) {
                        return res.status(401).json({ error: 'User not authenticated' });
                }

                // Hub check — return empty history silently if not in same hub
                if (!canPublicKeysConnect(publicKey, otherPublicKey)) {
                        return res.json({ messages: [] });
                }

                const messages = db.prepare(`
                        SELECT
                                m.id as messageId,
                                m.from_key as "from",
                                m.to_key as "to",
                                m.encrypted_content as encrypted,
                                m.timestamp,
                                m.type,
                                m.file_name as fileName,
                                m.mime_type as mimeType,
                                u.username as fromUsername
                        FROM messages m
                        LEFT JOIN users u ON m.from_key = u.public_key
                        WHERE (m.from_key = ? AND m.to_key = ?)
                                OR (m.from_key = ? AND m.to_key = ?)
                        ORDER BY m.created_at DESC
                        LIMIT ?
                `).all(publicKey, otherPublicKey, otherPublicKey, publicKey, parseInt(limit));

                messages.reverse();

                res.json({ messages });
        } catch (error) {
                console.error('Conversation fetch error:', error);
                res.status(500).json({ error: 'Failed to fetch conversation' });
        }
});

app.get('/users/network', (req, res) => {
        try {
                const { requester } = req.query;

                // Fetch all active users from the last 30 days
                const allUsers = db.prepare(`
                        SELECT public_key, username, last_seen, encryption_public_key
                        FROM users
                        WHERE last_seen > ?
                        ORDER BY last_seen DESC
                        LIMIT 200
                `).all(Date.now() - 30 * 24 * 60 * 60 * 1000);

                // Open mode — no hubs configured
                if (hubsConfig.hubs.length === 0) {
                        return res.json({ users: allUsers });
                }

                // Hub mode requires requester identity to filter
                if (!requester) {
                        return res.json({ users: [] });
                }

                const requesterKey = decodeURIComponent(requester);
                const requesterUser = db.prepare('SELECT username FROM users WHERE public_key = ?').get(requesterKey);

                if (!requesterUser) {
                        return res.json({ users: [] });
                }

                const reachable = getReachableUsernames(requesterUser.username);

                if (reachable === null) {
                        // Open mode fallback
                        return res.json({ users: allUsers });
                }

                // Return only hub-reachable users, excluding the requester themselves
                // Include hub-reachable users AND the requester themselves
                // (so the client can look up their own username/encryption key).
                // The Flutter UI already filters self out of the displayed list.
                const filteredUsers = allUsers.filter(u =>
                        reachable.has(u.username) || u.public_key === requesterKey
                );

                res.json({ users: filteredUsers });
        } catch (error) {
                console.error('Users fetch error:', error);
                res.status(500).json({ error: 'Failed to fetch users' });
        }
});

// ============================================================================
// STATIC FILE SERVING & HTML ROUTING
// ============================================================================

app.use(express.static(path.join(__dirname, 'site')));

app.use((req, res, next) => {
        if (req.path.startsWith('/auth') ||
            req.path.startsWith('/session') ||
            req.path.startsWith('/send') ||
            req.path.startsWith('/recv') ||
            req.path.startsWith('/conversation') ||
            req.path.startsWith('/users') ||
            req.path.startsWith('/health') ||
            req.path.startsWith('/welcome') ||
            path.extname(req.path)) {
                return next();
        }

        const htmlPath = path.join(__dirname, 'site', req.path + '.html');

        if (fs.existsSync(htmlPath)) {
                return res.sendFile(htmlPath);
        }

        next();
});

// ============================================================================
// ERROR HANDLING
// ============================================================================

app.use((req, res) => {
        res.status(404).sendFile(path.join(__dirname, 'site/404.html'));
});

app.use((err, req, res, next) => {
        console.error('Unhandled error:', err);
        res.status(500).json({ error: 'Internal server error' });
});

// ============================================================================
// START SERVER
// ============================================================================

server.listen(PORT, '127.0.0.1', () => {
        console.log('='.repeat(60));
        console.log('🔒 DEVOID HYPERSECURE SERVER');
        console.log('='.repeat(60));
        console.log(`🚀 HTTP Server: http://127.0.0.1:${PORT}`);
        console.log(`🔌 WebSocket Server: ws://127.0.0.1:${PORT}`);
        console.log(`🔐 TLS termination via nginx on port 8443`);
        console.log(`📊 Database: devoid.db`);
        console.log(`⏰ Started at: ${new Date().toISOString()}`);
        console.log('='.repeat(60));
        console.log('🔒 INVITE-ONLY MODE ACTIVE');
        console.log('  • Real-time WebSocket push notifications');
        console.log('  • Messages marked as delivered');
        console.log('  • Zero-knowledge encryption');
        console.log('  • Hub-based access control (hubs.json, hot-reload)');
        console.log('  • Media message support (images, videos, files up to ~37MB)');
        console.log('='.repeat(60));
});

process.on('SIGTERM', () => {
        console.log('SIGTERM received, closing server...');
        fs.unwatchFile(HUBS_FILE_PATH);
        wss.clients.forEach(client => client.close());
        db.close();
        process.exit(0);
});

process.on('SIGINT', () => {
        console.log('SIGINT received, closing server...');
        fs.unwatchFile(HUBS_FILE_PATH);
        wss.clients.forEach(client => client.close());
        db.close();
        process.exit(0);
});
