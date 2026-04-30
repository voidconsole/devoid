import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'api_client.dart';
import 'crypto_service.dart';

/// Session management with ephemeral key exchange
/// Implements forward secrecy using X25519 ECDH
class SessionService {
  final ApiClient _apiClient;
  final CryptoService _cryptoService;
  
  // In-memory session storage (never persisted to disk)
  SessionData? _currentSession;
  
  SessionService({
    required ApiClient apiClient,
    required CryptoService cryptoService,
  })  : _apiClient = apiClient,
        _cryptoService = cryptoService;

  /// Establishes a new secure session with the server
  /// 
  /// Flow:
  /// 1. Generate ephemeral X25519 keypair (client side)
  /// 2. Send client public key to server
  /// 3. Receive server's ephemeral public key
  /// 4. Perform ECDH to derive shared secret
  /// 5. Use HKDF to derive session key from shared secret
  /// 
  /// This provides forward secrecy: even if identity keys are compromised,
  /// past sessions remain secure because ephemeral keys are destroyed
  Future<SessionData> establishSession({
    required String userPublicKey,
    String? authToken,
  }) async {
    try {
      // Step 1: Generate fresh ephemeral keypair for this session
      // These keys will be destroyed after session establishment
     
      // Step 2: Send client ephemeral public key to server
     
      
      // Step 3: Perform X25519 ECDH to derive shared secret
      // Both client and server compute the same shared secret
      final sharedSecret = await _cryptoService.deriveX25519SharedSecret(
        localKeyPair: clientEphemeralKeyPair,
        remotePublicKeyBase64: serverEphemeralPublicKeyBase64,
      );
      
      // Step 4: Derive session key using HKDF-SHA256
      // HKDF ensures the key is cryptographically strong and properly distributed

      
      // Step 5: Store session in memory (never written to disk)
      
      return _currentSession!;
      
    } on ApiException catch (e) {
      throw SessionException('Network error during session establishment: ${e.message}');
    } catch (e) {
      throw SessionException('Failed to establish session: $e');
    }
  }

  /// Refreshes an existing session (renegotiates keys)
  /// Should be called periodically or when session expires
  Future<SessionData> refreshSession() async {
    if (_currentSession == null) {
      throw SessionException('No active session to refresh');
    }
    
    return await establishSession(
      userPublicKey: _currentSession!.userPublicKey,
    );
  }

  /// Gets the current active session
  SessionData? getCurrentSession() {
    // Check if session has expired (e.g., after 24 hours)
    if (_currentSession != null) {
      final age = DateTime.now().difference(_currentSession!.establishedAt);
      if (age.inHours >= 24) {
        // Session too old, clear it
        clearSession();
        return null;
      }
    }
    return _currentSession;
  }

  /// Checks if there's an active valid session
  bool hasActiveSession() {
    return getCurrentSession() != null;
  }

  /// Terminates the current session
  /// Clears session key from memory
  Future<void> terminateSession() async {
    if (_currentSession == null) {
      return;
    }
    
    try {
      // Notify server of session termination
      await _apiClient.post('/session/end', {
        'sessionId': _currentSession!.sessionId,
      });
    } catch (e) {
      // Log but don't throw - local cleanup is more important
      print('Failed to notify server of session termination: $e');
    } finally {
      clearSession();
    }
  }

  /// Clears session from memory
  /// Called on logout or session expiration
  void clearSession() {
    if (_currentSession != null) {
      // Overwrite session key bytes with zeros before clearing
      // This helps prevent key material from lingering in memory
      _currentSession!.sessionKey.fillRange(0, _currentSession!.sessionKey.length, 0);
      _currentSession = null;
    }
  }

  /// Generates a random session ID for client-side tracking
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = base64Encode(List.generate(16, (i) => i * timestamp % 256));
    return '$timestamp-$random';
  }
}

/// Session data stored in memory
/// CRITICAL: Never persisted to disk, cleared on logout
class SessionData {
  final String sessionId;
  final Uint8List sessionKey; // 32 bytes for AES-256/ChaCha20
  final String userPublicKey;
  final DateTime establishedAt;
  
  SessionData({
    required this.sessionId,
    required this.sessionKey,
    required this.userPublicKey,
    required this.establishedAt,
  });
  
  /// Checks if session is still valid (not expired)
  bool isValid({Duration maxAge = const Duration(hours: 24)}) {
    final age = DateTime.now().difference(establishedAt);
    return age < maxAge;
  }
}

/// Custom exception for session errors
class SessionException implements Exception {
  final String message;
  SessionException(this.message);
  
  @override
  String toString() => 'SessionException: $message';
}
