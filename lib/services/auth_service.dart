import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'api_client.dart';
import 'crypto_service.dart';

/// Authentication service using Ed25519 challenge-response
class AuthService {
  final ApiClient _apiClient;
  final CryptoService _cryptoService;

  AuthService({
    required ApiClient apiClient,
    required CryptoService cryptoService,
  })  : _apiClient = apiClient,
        _cryptoService = cryptoService;

  /// Authenticates user with the server
  Future<AuthResult> authenticate(String userPrivateKeyBase64) async {
    try {
      print('🔐 Starting authentication...');

      // Step 1: Request challenge
      print('  → Requesting challenge...');
      final challengeResponse = await _apiClient.get('/auth/challenge');

      if (challengeResponse.data == null ||
          challengeResponse.data['challenge'] == null) {
        throw AuthException('Invalid challenge response from server');
      }

      final challengeId = challengeResponse.data['challengeId'] as String;
      final challengeBase64 = challengeResponse.data['challenge'] as String;
      final challenge = base64Decode(challengeBase64);

      print('  ✓ Received challenge: ${challengeId.substring(0, 8)}...');

      // Step 2: Derive Ed25519 identity keypair
      print('  → Deriving Ed25519 keypair...');
      final identityKeyPair = await _cryptoService.ed25519KeyPairFromPrivateKey(
        userPrivateKeyBase64,
      );

      // Step 3: Sign the challenge
      print('  → Signing challenge...');
      final signature = await _cryptoService.signWithEd25519(
        identityKeyPair,
        Uint8List.fromList(challenge),
      );

      // Step 4: Get identity public key
      final publicKeyBase64 = await _cryptoService.getPublicKeyBase64(identityKeyPair);
      print('  → Identity public key: ${publicKeyBase64.substring(0, 12)}...');

      // Step 5: Derive X25519 encryption keypair from same seed
      final privateKeyBytes = base64Decode(userPrivateKeyBase64);
      final seed = privateKeyBytes.sublist(0, 32);
      final encryptionKeyPair = await _cryptoService.deriveX25519KeyPairFromEd25519Seed(seed);
      final encryptionPublicKeyBase64 = await _cryptoService.getPublicKeyBase64(encryptionKeyPair);

      print('  → Encryption public key: ${encryptionPublicKeyBase64.substring(0, 12)}...');

      // Step 6: Send both keys to server
      print('  → Verifying signature with server...');
      final verifyResponse = await _apiClient.post('/auth/verify', {
        'publicKey': publicKeyBase64,
        'signature': base64Encode(signature.bytes),
        'challenge': challengeBase64,
        'encryptionPublicKey': encryptionPublicKeyBase64, // Send encryption key
      });

      if (verifyResponse.data == null) {
        throw AuthException('Empty response from server');
      }

      if (verifyResponse.data['verified'] != true) {
        final errorMsg = verifyResponse.data['error'] as String? ??
            'Authentication failed';
        throw AuthException(errorMsg);
      }

      final sessionToken = verifyResponse.data['token'] as String?;

      print('  ✓ Authentication successful');

      return AuthResult(
        success: true,
        publicKey: publicKeyBase64,
        sessionToken: sessionToken,
      );

    } on ApiException catch (e) {
      print('  ✗ API error: ${e.message}');

      if (e.statusCode == 403) {
        throw AuthException('User not authorized. Contact admin for access.');
      } else if (e.statusCode == 401) {
        throw AuthException('Invalid credentials or expired challenge');
      }

      throw AuthException('Network error during authentication: ${e.message}');
    } catch (e) {
      print('  ✗ Authentication error: $e');
      throw AuthException('Authentication failed: $e');
    }
  }

  /// Checks if the server is reachable and healthy
  Future<bool> checkServerHealth() async {
    try {
      final response = await _apiClient.get('/health');
      return response.isSuccess && response.data?['status'] == 'ok';
    } catch (e) {
      print('  ✗ Health check failed: $e');
      return false;
    }
  }
}

/// Result of authentication attempt
class AuthResult {
  final bool success;
  final String? publicKey;
  final String? sessionToken;
  final String? errorMessage;

  AuthResult({
    required this.success,
    this.publicKey,
    this.sessionToken,
    this.errorMessage,
  });

  AuthResult.failure(String error)
      : success = false,
        publicKey = null,
        sessionToken = null,
        errorMessage = error;
}

/// Custom exception for authentication errors
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}