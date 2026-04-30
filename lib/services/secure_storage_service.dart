import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage interface for sensitive data
/// Uses platform-specific secure storage (Keychain on iOS, Keystore on Android)
class SecureStorageService {
  final FlutterSecureStorage _storage;
  
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock,
          ),
        );

  // Storage keys
  static const String _keyUserPrivateKey = 'user_private_key';
  static const String _keyServerFingerprint = 'server_fingerprint';
  static const String _keyServerAddress = 'server_address';
  static const String _keyUserPublicKey = 'user_public_key';

  /// Stores user's private Ed25519 key (base64-encoded)
  /// CRITICAL: This key must never be logged or exposed
  Future<void> storeUserPrivateKey(String privateKeyBase64) async {
    try {
      await _storage.write(
        key: _keyUserPrivateKey,
        value: privateKeyBase64,
      );
    } catch (e) {
      throw StorageException('Failed to store private key: $e');
    }
  }

  /// Retrieves user's private key
  /// Returns null if not found
  Future<String?> getUserPrivateKey() async {
    try {
      return await _storage.read(key: _keyUserPrivateKey);
    } catch (e) {
      throw StorageException('Failed to read private key: $e');
    }
  }

  /// Stores user's public key (for convenience)
  Future<void> storeUserPublicKey(String publicKeyBase64) async {
    try {
      await _storage.write(
        key: _keyUserPublicKey,
        value: publicKeyBase64,
      );
    } catch (e) {
      throw StorageException('Failed to store public key: $e');
    }
  }

  /// Retrieves user's public key
  Future<String?> getUserPublicKey() async {
    try {
      return await _storage.read(key: _keyUserPublicKey);
    } catch (e) {
      throw StorageException('Failed to read public key: $e');
    }
  }

  /// Stores server's certificate fingerprint for pinning
  Future<void> storeServerFingerprint(String fingerprint) async {
    try {
      await _storage.write(
        key: _keyServerFingerprint,
        value: fingerprint,
      );
    } catch (e) {
      throw StorageException('Failed to store server fingerprint: $e');
    }
  }

  /// Retrieves server fingerprint
  Future<String?> getServerFingerprint() async {
    try {
      return await _storage.read(key: _keyServerFingerprint);
    } catch (e) {
      throw StorageException('Failed to read server fingerprint: $e');
    }
  }

  /// Stores server address
  Future<void> storeServerAddress(String address) async {
    try {
      await _storage.write(
        key: _keyServerAddress,
        value: address,
      );
    } catch (e) {
      throw StorageException('Failed to store server address: $e');
    }
  }

  /// Retrieves server address
  Future<String?> getServerAddress() async {
    try {
      return await _storage.read(key: _keyServerAddress);
    } catch (e) {
      throw StorageException('Failed to read server address: $e');
    }
  }

  /// Checks if user credentials are stored
  Future<bool> hasUserCredentials() async {
    final privateKey = await getUserPrivateKey();
    return privateKey != null && privateKey.isNotEmpty;
  }

  /// Checks if server configuration is stored
  Future<bool> hasServerConfig() async {
    final fingerprint = await getServerFingerprint();
    final address = await getServerAddress();
    return fingerprint != null && 
           fingerprint.isNotEmpty && 
           address != null && 
           address.isNotEmpty;
  }

  /// Deletes all stored credentials and configuration
  /// Called on logout or account deletion
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      throw StorageException('Failed to clear storage: $e');
    }
  }

  /// Deletes only user credentials (keeps server config)
  Future<void> clearUserCredentials() async {
    try {
      await _storage.delete(key: _keyUserPrivateKey);
      await _storage.delete(key: _keyUserPublicKey);
    } catch (e) {
      throw StorageException('Failed to clear credentials: $e');
    }
  }

  /// Reads all stored keys (for debugging - use carefully)
  /// NEVER log the actual values of private keys
  Future<Map<String, String>> readAllKeys() async {
    try {
      return await _storage.readAll();
    } catch (e) {
      throw StorageException('Failed to read all keys: $e');
    }
  }
}

/// Custom exception for storage operations
class StorageException implements Exception {
  final String message;
  StorageException(this.message);
  
  @override
  String toString() => 'StorageException: $message';
}
