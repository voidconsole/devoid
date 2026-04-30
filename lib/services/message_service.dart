import 'dart:convert';
import 'dart:typed_data';
import 'api_client.dart';
import 'crypto_service.dart';
import 'secure_storage_service.dart';
import 'local_message_storage.dart';

/// Message encryption, decryption, and transmission service.
/// Supports both text and binary media (images, videos, files).
///
/// Media encoding strategy:
///   plaintext  = base64(fileBytes)
///   ciphertext = AES-GCM-256(plaintext, pairwiseKey)
///
/// This keeps the crypto path identical for text and media.
/// The unencrypted envelope (type, fileName, mimeType) travels alongside
/// the ciphertext so the server can route and the UI can render correctly.
class MessageService {
  final ApiClient _apiClient;
  final CryptoService _cryptoService;
  final SecureStorageService _storage;
  final LocalMessageStorage _localStorage;

  // Cache for other users' encryption public keys (avoids repeated /users/network calls)
  final Map<String, String> _encryptionKeyCache = {};

  MessageService({
    required ApiClient apiClient,
    required CryptoService cryptoService,
    required SecureStorageService storage,
    required LocalMessageStorage localStorage,
  })  : _apiClient = apiClient,
        _cryptoService = cryptoService,
        _storage = storage,
        _localStorage = localStorage;

  // ──────────────────────────────────────────────────────────
  // SEND
  // ──────────────────────────────────────────────────────────

  /// Sends an encrypted text message.
  Future<SendMessageResult> sendMessage({
    required String recipientPublicKey,
    required String plaintext,
  }) async {
    try {
      print('📤 Encrypting text message...');

      final myPrivateKey = await _storage.getUserPrivateKey();
      if (myPrivateKey == null) throw MessageException('No user credentials found');

      final myPublicKey = await _storage.getUserPublicKey();
      if (myPublicKey == null) throw MessageException('No user public key found');

      final recipientEncryptionKey = await _getEncryptionKey(recipientPublicKey);

      final pairwiseKey = await _cryptoService.derivePairwiseKey(
        myPrivateKeyBase64: myPrivateKey,
        otherUserEncryptionPublicKeyBase64: recipientEncryptionKey,
      );

      final encryptedMessage = await _cryptoService.encryptMessage(
        plaintext: plaintext,
        sessionKey: pairwiseKey,
      );

      final messagePackage = {
        'from': myPublicKey,
        'to': recipientPublicKey,
        'encrypted': encryptedMessage,
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'text',
      };

      final response = await _apiClient.post('/send', messagePackage);

      final messageId = response.data?['messageId'] as String?;
      final success = response.data?['success'] == true;

      if (success && messageId != null) {
        await _localStorage.storeSentMessage(
          messageId: messageId,
          recipientPublicKey: recipientPublicKey,
          plaintext: plaintext,
          timestamp: DateTime.now(),
        );
        print('  ✓ Text message sent and stored locally: $messageId');
      }

      return SendMessageResult(
        success: success,
        messageId: messageId,
        timestamp: DateTime.now(),
      );
    } on ApiException catch (e) {
      print('  ✗ Send failed: ${e.message}');
      if (e.statusCode == 401) throw MessageException('Not authenticated. Please reconnect.');
      if (e.statusCode == 403) throw MessageException('Messaging not permitted with this user.');
      if (e.statusCode == 404) throw MessageException('Recipient not found or not authorized.');
      throw MessageException('Failed to send message: ${e.message}');
    } catch (e) {
      print('  ✗ Error: $e');
      throw MessageException('Message encryption failed: $e');
    }
  }

  /// Sends an encrypted media message (image, video, or arbitrary file).
  ///
  /// The binary [fileBytes] are base64-encoded to produce the "plaintext",
  /// which is then encrypted with AES-GCM using the pairwise key.
  /// This keeps all crypto identical to text — the server sees only
  /// ciphertext plus unencrypted metadata (type, fileName, mimeType).
  Future<SendMessageResult> sendMedia({
    required String recipientPublicKey,
    required Uint8List fileBytes,
    required String mimeType,
    required String fileName,
    required String type, // 'image' | 'video' | 'file'
  }) async {
    try {
      print('📤 Encrypting $type ($fileName, ${fileBytes.length} bytes)...');

      final myPrivateKey = await _storage.getUserPrivateKey();
      if (myPrivateKey == null) throw MessageException('No user credentials found');

      final myPublicKey = await _storage.getUserPublicKey();
      if (myPublicKey == null) throw MessageException('No user public key found');

      final recipientEncryptionKey = await _getEncryptionKey(recipientPublicKey);

      final pairwiseKey = await _cryptoService.derivePairwiseKey(
        myPrivateKeyBase64: myPrivateKey,
        otherUserEncryptionPublicKeyBase64: recipientEncryptionKey,
      );

      // Encode the binary payload as base64 — this becomes the AES-GCM plaintext
      final base64Data = base64Encode(fileBytes);

      final encryptedMessage = await _cryptoService.encryptMessage(
        plaintext: base64Data,
        sessionKey: pairwiseKey,
      );

      final messagePackage = {
        'from': myPublicKey,
        'to': recipientPublicKey,
        'encrypted': encryptedMessage,
        'timestamp': DateTime.now().toIso8601String(),
        'type': type,
        'fileName': fileName,
        'mimeType': mimeType,
      };

      final response = await _apiClient.post('/send', messagePackage);

      final messageId = response.data?['messageId'] as String?;
      final success = response.data?['success'] == true;

      // We intentionally do NOT store media in local storage.
      // The pairwise key is symmetric, so we can always re-decrypt our own
      // sent media from the server when loading conversation history.
      if (success) {
        print('  ✓ Media sent: $messageId');
      }

      return SendMessageResult(
        success: success,
        messageId: messageId,
        timestamp: DateTime.now(),
      );
    } on ApiException catch (e) {
      print('  ✗ Media send failed: ${e.message}');
      if (e.statusCode == 403) throw MessageException('Messaging not permitted with this user.');
      if (e.statusCode == 404) throw MessageException('Recipient not found.');
      throw MessageException('Failed to send media: ${e.message}');
    } catch (e) {
      print('  ✗ Error: $e');
      throw MessageException('Media encryption failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // RECEIVE
  // ──────────────────────────────────────────────────────────

  /// Polls the server for undelivered incoming messages and decrypts them.
  Future<List<ReceivedMessage>> receiveMessages() async {
    try {
      final myPrivateKey = await _storage.getUserPrivateKey();
      final myPublicKey = await _storage.getUserPublicKey();

      if (myPrivateKey == null || myPublicKey == null) {
        throw MessageException('No user credentials found');
      }

      final encodedPublicKey = Uri.encodeComponent(myPublicKey);
      final response = await _apiClient.get('/recv/$encodedPublicKey');

      if (response.data == null || response.data['messages'] == null) return [];

      final messagesJson = response.data['messages'] as List;
      if (messagesJson.isEmpty) return [];

      print('📥 Received ${messagesJson.length} message(s)');

      final decryptedMessages = <ReceivedMessage>[];

      for (final messageData in messagesJson) {
        try {
          final encrypted = messageData['encrypted'] as String;
          final from = messageData['from'] as String;
          final messageId = messageData['messageId'] as String?;
          final timestamp = messageData['timestamp'] as String?;
          final type = (messageData['type'] as String?) ?? 'text';
          final mimeType = messageData['mimeType'] as String?;
          final fileName = messageData['fileName'] as String?;

          final senderEncryptionKey = await _getEncryptionKey(from);

          final pairwiseKey = await _cryptoService.derivePairwiseKey(
            myPrivateKeyBase64: myPrivateKey,
            otherUserEncryptionPublicKeyBase64: senderEncryptionKey,
          );

          final plaintext = await _cryptoService.decryptMessage(
            ciphertextBase64: encrypted,
            sessionKey: pairwiseKey,
          );

          // For media messages, decode the base64 plaintext back to raw bytes
          Uint8List? mediaBytes;
          if (type != 'text') {
            try {
              mediaBytes = base64Decode(plaintext);
            } catch (e) {
              print('  ⚠️ Failed to decode media bytes: $e');
            }
          }

          decryptedMessages.add(ReceivedMessage(
            messageId: messageId,
            from: from,
            plaintext: plaintext,
            timestamp: timestamp != null ? DateTime.parse(timestamp) : DateTime.now(),
            type: type,
            mimeType: mimeType,
            fileName: fileName,
            mediaBytes: mediaBytes,
          ));
        } catch (e) {
          print('  ⚠️ Failed to decrypt message: $e');
        }
      }

      print('  ✓ Decrypted ${decryptedMessages.length} message(s)');
      return decryptedMessages;
    } on ApiException catch (e) {
      throw MessageException('Failed to receive messages: ${e.message}');
    } catch (e) {
      throw MessageException('Message retrieval failed: $e');
    }
  }

  /// Loads full conversation history with another user.
  Future<List<ReceivedMessage>> getConversation({
    required String otherPublicKey,
    int? limit,
  }) async {
    try {
      final myPrivateKey = await _storage.getUserPrivateKey();
      final myPublicKey = await _storage.getUserPublicKey();

      if (myPrivateKey == null || myPublicKey == null) {
        throw MessageException('No user credentials found');
      }

      final encodedPublicKey = Uri.encodeComponent(myPublicKey);
      final encodedOtherKey = Uri.encodeComponent(otherPublicKey);

      final queryString = [
        'other=$encodedOtherKey',
        if (limit != null) 'limit=$limit',
      ].join('&');

      print('📜 Loading conversation history...');

      final response = await _apiClient.get(
        '/conversation/$encodedPublicKey?$queryString',
      );

      if (response.data == null || response.data['messages'] == null) return [];

      final messagesJson = response.data['messages'] as List;
      if (messagesJson.isEmpty) return [];

      print('  → Decrypting ${messagesJson.length} message(s)...');

      // Derive the single pairwise key shared between the two users
      final otherEncryptionKey = await _getEncryptionKey(otherPublicKey);
      final pairwiseKey = await _cryptoService.derivePairwiseKey(
        myPrivateKeyBase64: myPrivateKey,
        otherUserEncryptionPublicKeyBase64: otherEncryptionKey,
      );

      final decryptedMessages = <ReceivedMessage>[];

      for (final messageData in messagesJson) {
        try {
          final encrypted = messageData['encrypted'] as String;
          final from = messageData['from'] as String;
          final messageId = messageData['messageId'] as String?;
          final timestamp = messageData['timestamp'] as String?;
          final type = (messageData['type'] as String?) ?? 'text';
          final mimeType = messageData['mimeType'] as String?;
          final fileName = messageData['fileName'] as String?;

          String plaintext;

          if (from == myPublicKey) {
            // Message we sent — check local storage first (text only)
            if (type == 'text') {
              final stored = await _localStorage.getSentMessage(messageId ?? '');
              if (stored != null) {
                plaintext = stored.plaintext;
                print('  ✓ Retrieved own text from local storage');
              } else {
                // Fall back to server decryption (symmetric key works for our own messages)
                try {
                  plaintext = await _cryptoService.decryptMessage(
                    ciphertextBase64: encrypted,
                    sessionKey: pairwiseKey,
                  );
                  print('  ✓ Decrypted own text from server');
                } catch (e) {
                  print('  ⚠️ Skipping own message — not in local storage and decryption failed: $e');
                  continue;
                }
              }
            } else {
              // Media we sent — always re-decrypt from server (no local cache for media)
              try {
                plaintext = await _cryptoService.decryptMessage(
                  ciphertextBase64: encrypted,
                  sessionKey: pairwiseKey,
                );
              } catch (e) {
                print('  ⚠️ Failed to decrypt own media: $e');
                continue;
              }
            }
          } else {
            // Message from the other person — decrypt normally
            plaintext = await _cryptoService.decryptMessage(
              ciphertextBase64: encrypted,
              sessionKey: pairwiseKey,
            );
          }

          // Decode media bytes post-decryption
          Uint8List? mediaBytes;
          if (type != 'text') {
            try {
              mediaBytes = base64Decode(plaintext);
            } catch (e) {
              print('  ⚠️ Failed to decode media bytes: $e');
            }
          }

          decryptedMessages.add(ReceivedMessage(
            messageId: messageId,
            from: from,
            plaintext: plaintext,
            timestamp: timestamp != null ? DateTime.parse(timestamp) : DateTime.now(),
            type: type,
            mimeType: mimeType,
            fileName: fileName,
            mediaBytes: mediaBytes,
          ));
        } catch (e) {
          print('  ⚠️ Failed to process message: $e');
        }
      }

      print('  ✓ Loaded ${decryptedMessages.length} message(s)');
      return decryptedMessages;
    } catch (e) {
      throw MessageException('Failed to get conversation: $e');
    }
  }

  /// Decrypts a single incoming message delivered via WebSocket.
  Future<ReceivedMessage?> decryptIncomingMessage(Map<String, dynamic> messageData) async {
    try {
      final myPrivateKey = await _storage.getUserPrivateKey();
      final myPublicKey = await _storage.getUserPublicKey();

      if (myPrivateKey == null || myPublicKey == null) {
        throw MessageException('No user credentials found');
      }

      final encrypted = messageData['encrypted'] as String;
      final from = messageData['from'] as String;
      final messageId = messageData['messageId'] as String?;
      final timestamp = messageData['timestamp'] as String?;
      final type = (messageData['type'] as String?) ?? 'text';
      final mimeType = messageData['mimeType'] as String?;
      final fileName = messageData['fileName'] as String?;

      final senderEncryptionKey = await _getEncryptionKey(from);

      final pairwiseKey = await _cryptoService.derivePairwiseKey(
        myPrivateKeyBase64: myPrivateKey,
        otherUserEncryptionPublicKeyBase64: senderEncryptionKey,
      );

      final plaintext = await _cryptoService.decryptMessage(
        ciphertextBase64: encrypted,
        sessionKey: pairwiseKey,
      );

      Uint8List? mediaBytes;
      if (type != 'text') {
        try {
          mediaBytes = base64Decode(plaintext);
        } catch (e) {
          print('  ⚠️ Failed to decode incoming media bytes: $e');
        }
      }

      return ReceivedMessage(
        messageId: messageId,
        from: from,
        plaintext: plaintext,
        timestamp: timestamp != null ? DateTime.parse(timestamp) : DateTime.now(),
        type: type,
        mimeType: mimeType,
        fileName: fileName,
        mediaBytes: mediaBytes,
      );
    } catch (e) {
      print('  ⚠️ Failed to decrypt incoming message: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────
  // INTERNAL HELPERS
  // ──────────────────────────────────────────────────────────

  /// Fetches the X25519 encryption public key for a user, with in-memory caching.
  Future<String> _getEncryptionKey(String userPublicKey) async {
    if (_encryptionKeyCache.containsKey(userPublicKey)) {
      return _encryptionKeyCache[userPublicKey]!;
    }

    try {
      // Pass our own key as requester so the server applies hub filtering
      // and returns the list (including ourselves for self-lookup).
      final myPublicKey = await _storage.getUserPublicKey();
      String networkEndpoint = '/users/network';
      if (myPublicKey != null && myPublicKey.isNotEmpty) {
        networkEndpoint =
            '/users/network?requester=${Uri.encodeComponent(myPublicKey)}';
      }
      final response = await _apiClient.get(networkEndpoint);

      if (response.data == null || response.data['users'] == null) {
        throw MessageException('No users data from server');
      }

      final users = response.data['users'] as List;

      for (final user in users) {
        try {
          final pubKey = user['public_key'] as String;
          final encKey = user['encryption_public_key'] as String?;
          if (encKey != null && encKey.isNotEmpty) {
            _encryptionKeyCache[pubKey] = encKey;
          }
        } catch (e) {
          continue;
        }
      }

      if (_encryptionKeyCache.containsKey(userPublicKey)) {
        return _encryptionKeyCache[userPublicKey]!;
      }

      throw MessageException(
        'Encryption key not found for ${userPublicKey.substring(0, 12)}...',
      );
    } catch (e) {
      if (e is MessageException) rethrow;
      throw MessageException('Failed to get encryption key: $e');
    }
  }

  /// Clears the encryption key cache (call after user list changes).
  void clearEncryptionKeyCache() {
    _encryptionKeyCache.clear();
    print('🗑️ Encryption key cache cleared');
  }
}

// ──────────────────────────────────────────────────────────
// DATA CLASSES
// ──────────────────────────────────────────────────────────

class SendMessageResult {
  final bool success;
  final String? messageId;
  final DateTime timestamp;
  final String? error;

  SendMessageResult({
    required this.success,
    this.messageId,
    required this.timestamp,
    this.error,
  });

  SendMessageResult.failure(String errorMessage)
      : success = false,
        messageId = null,
        timestamp = DateTime.now(),
        error = errorMessage;
}

/// A message received from the network (decrypted and ready for the UI).
class ReceivedMessage {
  final String? messageId;
  final String from;

  /// For text messages: the plaintext string.
  /// For media messages: the base64-encoded bytes (use [mediaBytes] instead).
  final String plaintext;

  final DateTime timestamp;

  /// 'text' | 'image' | 'video' | 'file'
  final String type;

  /// MIME type for media messages, e.g. 'image/jpeg'.
  final String? mimeType;

  /// Original filename for video and file messages.
  final String? fileName;

  /// Decoded binary data for media messages. Null for text.
  final Uint8List? mediaBytes;

  ReceivedMessage({
    this.messageId,
    required this.from,
    required this.plaintext,
    required this.timestamp,
    this.type = 'text',
    this.mimeType,
    this.fileName,
    this.mediaBytes,
  });

  bool get isMedia => type != 'text';
}

class MessageException implements Exception {
  final String message;
  MessageException(this.message);

  @override
  String toString() => 'MessageException: $message';
}