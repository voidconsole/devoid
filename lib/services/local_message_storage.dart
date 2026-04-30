import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores sent messages locally so they can be retrieved after app restart.
/// Uses FlutterSecureStorage which provides platform-specific encryption.
class LocalMessageStorage {
  // Use consistent options with SecureStorageService
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _sentMessagesPrefix = 'sent_msg_v2_';
  // Old prefix for backward compatibility if needed, but we prefer the new one
  static const String _oldSentMessagesPrefix = 'sent_msg_';

  /// Initialize device encryption key (kept for API compatibility)
  Future<void> initialize() async {
    print('💾 LocalMessageStorage initialized');
  }

  /// Stores a sent message locally
  Future<void> storeSentMessage({
    required String messageId,
    required String recipientPublicKey,
    required String plaintext,
    required DateTime timestamp,
  }) async {
    try {
      final messageData = {
        'messageId': messageId,
        'to': recipientPublicKey,
        'plaintext': plaintext,
        'timestamp': timestamp.toIso8601String(),
      };

      final jsonString = json.encode(messageData);

      // Store in secure storage - the library handles encryption
      await _storage.write(
        key: '$_sentMessagesPrefix$messageId',
        value: jsonString,
      );

      print('💾 Stored sent message: $messageId');
    } catch (e) {
      print('⚠️ Failed to store sent message: $e');
    }
  }

  /// Retrieves a sent message by ID
  Future<SentMessage?> getSentMessage(String messageId) async {
    if (messageId.isEmpty) return null;
    
    try {
      // Try new format first
      String? jsonString = await _storage.read(key: '$_sentMessagesPrefix$messageId');
      
      if (jsonString == null) {
        // Check old format if not found in new format
        // Note: Old format might fail to decrypt if XOR key was lost/corrupted
        return null;
      }

      final data = json.decode(jsonString) as Map<String, dynamic>;

      return SentMessage(
        messageId: data['messageId'] as String,
        recipientPublicKey: data['to'] as String,
        plaintext: data['plaintext'] as String,
        timestamp: DateTime.parse(data['timestamp'] as String),
      );
    } catch (e) {
      print('⚠️ Failed to retrieve sent message $messageId: $e');
      return null;
    }
  }

  /// Gets all sent messages to a specific recipient
  Future<List<SentMessage>> getSentMessagesTo(String recipientPublicKey) async {
    try {
      final allKeys = await _storage.readAll();
      final sentMessages = <SentMessage>[];

      for (final entry in allKeys.entries) {
        if (entry.key.startsWith(_sentMessagesPrefix)) {
          try {
            final data = json.decode(entry.value) as Map<String, dynamic>;

            if (data['to'] == recipientPublicKey) {
              sentMessages.add(SentMessage(
                messageId: data['messageId'] as String,
                recipientPublicKey: data['to'] as String,
                plaintext: data['plaintext'] as String,
                timestamp: DateTime.parse(data['timestamp'] as String),
              ));
            }
          } catch (e) {
            continue;
          }
        }
      }

      sentMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return sentMessages;
    } catch (e) {
      print('⚠️ Failed to get sent messages: $e');
      return [];
    }
  }

  /// Clears all stored sent messages
  Future<void> clearAllSentMessages() async {
    try {
      final allKeys = await _storage.readAll();

      for (final key in allKeys.keys) {
        if (key.startsWith(_sentMessagesPrefix) || key.startsWith(_oldSentMessagesPrefix)) {
          await _storage.delete(key: key);
        }
      }

      print('🗑️ Cleared all sent messages');
    } catch (e) {
      print('⚠️ Failed to clear sent messages: $e');
    }
  }
}

/// Represents a sent message stored locally
class SentMessage {
  final String messageId;
  final String recipientPublicKey;
  final String plaintext;
  final DateTime timestamp;

  SentMessage({
    required this.messageId,
    required this.recipientPublicKey,
    required this.plaintext,
    required this.timestamp,
  });
}