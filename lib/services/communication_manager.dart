import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/network_user.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'crypto_service.dart';
import 'message_service.dart';
import 'secure_storage_service.dart';
import 'session_service.dart';
import 'websocket_service.dart';
import 'local_message_storage.dart';
import 'notification_service.dart';

/// High-level communication manager.
/// Orchestrates all services and provides a clean interface for the UI.
class CommunicationManager extends ChangeNotifier {
  final SecureStorageService _storage;
  final NotificationService? _notificationService;

  late final CryptoService _cryptoService;
  late final WebSocketService _webSocketService;
  late final LocalMessageStorage _localStorage;
  late ApiClient? _apiClient;
  late AuthService? _authService;
  late SessionService? _sessionService;
  late MessageService? _messageService;

  bool _isInitialized = false;
  String? _userPublicKey;
  String? _currentUsername;
  StreamSubscription? _webSocketSubscription;

  // Track senders with unread messages
  final Set<String> _unreadPublicKeys = {};
  String? _activeChatPublicKey;

  // Broadcast stream for real-time message delivery to the UI
  final StreamController<ReceivedMessage> _messageStreamController =
      StreamController<ReceivedMessage>.broadcast();

  Stream<ReceivedMessage> get messageStream => _messageStreamController.stream;

  CommunicationManager({
    required SecureStorageService storage,
    NotificationService? notificationService,
  })  : _storage = storage,
        _notificationService = notificationService {
    _cryptoService = CryptoService();
    _webSocketService = WebSocketService();
    _localStorage = LocalMessageStorage();
  }

  // ──────────────────────────────────────────────────────────
  // UNREAD TRACKING
  // ──────────────────────────────────────────────────────────

  void setActiveChat(String? publicKey) {
    _activeChatPublicKey = publicKey;
    if (publicKey != null) {
      _unreadPublicKeys.remove(publicKey);
      notifyListeners();
    }
  }

  bool hasUnreadFrom(String publicKey) => _unreadPublicKeys.contains(publicKey);

  void clearUnread(String publicKey) {
    if (_unreadPublicKeys.remove(publicKey)) notifyListeners();
  }

  // ──────────────────────────────────────────────────────────
  // LIFECYCLE
  // ──────────────────────────────────────────────────────────

  /// Initialises all services. Must be called before [connect].
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🔧 Initializing CommunicationManager...');

      await _localStorage.initialize();

      final serverAddress = await _storage.getServerAddress();
      final serverFingerprint = await _storage.getServerFingerprint();

      if (serverAddress == null || serverFingerprint == null) {
        throw InitializationException(
          'Server configuration not found. Please complete handshake first.',
        );
      }

      _apiClient = ApiClient(
        serverAddress: serverAddress,
        pinnedFingerprint: serverFingerprint,
      );

      _authService = AuthService(
        apiClient: _apiClient!,
        cryptoService: _cryptoService,
      );

      _sessionService = SessionService(
        apiClient: _apiClient!,
        cryptoService: _cryptoService,
      );

      _messageService = MessageService(
        apiClient: _apiClient!,
        cryptoService: _cryptoService,
        storage: _storage,
        localStorage: _localStorage,
      );

      _userPublicKey = await _storage.getUserPublicKey();

      _isInitialized = true;
      print('✓ CommunicationManager initialized');
    } catch (e) {
      throw InitializationException('Failed to initialize: $e');
    }
  }

  Future<void> _connectWebSocket() async {
    try {
      final serverAddress = await _storage.getServerAddress();
      if (serverAddress == null || _userPublicKey == null) return;

      await _webSocketService.connect(
        serverAddress: serverAddress,
        userPublicKey: _userPublicKey!,
      );
    } catch (e) {
      print('✗ WebSocket connection failed: $e');
    }
  }

  void _listenToWebSocket() {
    _webSocketSubscription?.cancel();
    _webSocketSubscription =
        _webSocketService.messageStream.listen((data) async {
      try {
        final receivedMessage =
            await _messageService?.decryptIncomingMessage(data);
        if (receivedMessage != null) {
          _processIncomingMessage(receivedMessage);
        }
      } catch (e) {
        print('✗ Error processing WebSocket message: $e');
      }
    });
  }

  void _processIncomingMessage(ReceivedMessage message) {
    _messageStreamController.add(message);

    if (message.from != _userPublicKey) {
      _unreadPublicKeys.add(message.from);

      if (message.from != _activeChatPublicKey) {
        _showIncomingMessageNotification(message);
      }

      notifyListeners();
    }
  }

  Future<void> _showIncomingMessageNotification(
      ReceivedMessage message) async {
    if (_notificationService == null) return;

    try {
      final users = await getNetworkUsers();
      final sender = users.firstWhere(
        (u) => u.publicKey == message.from,
        orElse: () =>
            NetworkUser(publicKey: message.from, name: 'New Message', icon: '?'),
      );

      // Human-readable body — never show raw base64 for media
      final String notifBody;
      switch (message.type) {
        case 'image':
          notifBody = '📷 Image';
          break;
        case 'video':
          notifBody = '🎥 Video';
          break;
        case 'file':
          notifBody = '📎 ${message.fileName ?? 'File'}';
          break;
        default:
          notifBody = message.plaintext;
      }

      await _notificationService?.showNotification(
        id: message.from.hashCode,
        title: sender.name,
        body: notifBody,
        payload: message.from,
      );
    } catch (e) {
      print('⚠️ Failed to show notification: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // CONNECTION
  // ──────────────────────────────────────────────────────────

  Future<ConnectionResult> connect() async {
    _ensureInitialized();

    try {
      print('🔌 Connecting to NEXUS network...');

      final privateKey = await _storage.getUserPrivateKey();
      if (privateKey == null) {
        return ConnectionResult.failure('No user credentials found');
      }

      try {
        final isHealthy = await _authService!.checkServerHealth();
        if (!isHealthy) {
          return ConnectionResult.failure('Server is unreachable or unhealthy');
        }
      } catch (e) {
        return ConnectionResult.failure('Cannot reach server: $e');
      }

      AuthResult authResult;
      try {
        authResult = await _authService!.authenticate(privateKey);
      } catch (e) {
        return ConnectionResult.failure('Authentication failed: $e');
      }

      if (!authResult.success) {
        return ConnectionResult.failure(
            authResult.errorMessage ?? 'Authentication failed');
      }

      _userPublicKey = authResult.publicKey;

      if (_userPublicKey != null) {
        await _storage.storeUserPublicKey(_userPublicKey!);
      }

      SessionData session;
      try {
        session = await _sessionService!.establishSession(
          userPublicKey: _userPublicKey!,
          authToken: authResult.sessionToken,
        );
      } catch (e) {
        return ConnectionResult.failure('Session establishment failed: $e');
      }

      await _fetchCurrentUserInfo();
      await _connectWebSocket();
      _listenToWebSocket();

      print('✓ Connected to NEXUS network');

      return ConnectionResult(
        success: true,
        publicKey: _userPublicKey,
        sessionId: session.sessionId,
        username: _currentUsername,
      );
    } catch (e) {
      return ConnectionResult.failure('Connection failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // MESSAGING
  // ──────────────────────────────────────────────────────────

  /// Sends a plain-text encrypted message.
  Future<SendMessageResult> sendMessage({
    required String recipientPublicKey,
    required String message,
  }) async {
    _ensureInitialized();
    _ensureConnected();

    try {
      return await _messageService!.sendMessage(
        recipientPublicKey: recipientPublicKey,
        plaintext: message,
      );
    } catch (e) {
      return SendMessageResult.failure('Failed to send: $e');
    }
  }

  /// Sends an encrypted media file (image, video, or arbitrary file).
  ///
  /// [fileBytes] must be ≤ 10 MB raw (enforced here and in the UI layer).
  /// [type] should be 'image', 'video', or 'file'.
  Future<SendMessageResult> sendMedia({
    required String recipientPublicKey,
    required Uint8List fileBytes,
    required String mimeType,
    required String fileName,
    required String type,
  }) async {
    _ensureInitialized();
    _ensureConnected();

    try {
      return await _messageService!.sendMedia(
        recipientPublicKey: recipientPublicKey,
        fileBytes: fileBytes,
        mimeType: mimeType,
        fileName: fileName,
        type: type,
      );
    } catch (e) {
      return SendMessageResult.failure('Failed to send media: $e');
    }
  }

  Future<List<ReceivedMessage>> receiveMessages() async {
    _ensureInitialized();
    _ensureConnected();

    try {
      final messages = await _messageService!.receiveMessages();
      for (final msg in messages) {
        _processIncomingMessage(msg);
      }
      return messages;
    } catch (e) {
      return [];
    }
  }

  Future<List<ReceivedMessage>> getConversation({
    required String otherPublicKey,
    int limit = 50,
  }) async {
    _ensureInitialized();
    _ensureConnected();

    try {
      return await _messageService!.getConversation(
        otherPublicKey: otherPublicKey,
        limit: limit,
      );
    } catch (e) {
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────
  // NETWORK USERS (hub-filtered)
  // ──────────────────────────────────────────────────────────

  /// Returns the list of users reachable by the current user.
  /// Passes the requester's public key to let the server apply hub filtering.
  Future<List<NetworkUser>> getNetworkUsers() async {
    _ensureInitialized();

    try {
      // Pass our public key so the server can return only hub-reachable users
      String endpoint = '/users/network';
      if (_userPublicKey != null && _userPublicKey!.isNotEmpty) {
        final encoded = Uri.encodeComponent(_userPublicKey!);
        endpoint = '/users/network?requester=$encoded';
      }

      final response = await _apiClient!.get(endpoint);

      if (response.data == null || response.data['users'] == null) return [];

      final usersJson = response.data['users'] as List;
      final networkUsers = <NetworkUser>[];

      for (final userData in usersJson) {
        try {
          networkUsers
              .add(NetworkUser.fromJson(userData as Map<String, dynamic>));
        } catch (e) {
          continue;
        }
      }

      return networkUsers;
    } catch (e) {
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────
  // SESSION & MISC
  // ──────────────────────────────────────────────────────────

  Future<bool> refreshSession() async {
    _ensureInitialized();
    try {
      if (_userPublicKey == null) return false;
      await _sessionService!.refreshSession();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> disconnect() async {
    if (!_isInitialized) return;
    try {
      await _webSocketService.disconnect();
      _webSocketSubscription?.cancel();
      await _sessionService?.terminateSession();
      _apiClient?.dispose();
    } catch (e) {
      print('⚠️ Error during disconnect: $e');
    }
  }

  Future<void> logout() async {
    await disconnect();
    await _storage.clearUserCredentials();
    await _localStorage.clearAllSentMessages();
    _userPublicKey = null;
    _currentUsername = null;
    _isInitialized = false;
    _unreadPublicKeys.clear();
    notifyListeners();
  }

  bool isConnected() {
    return _isInitialized && _sessionService?.hasActiveSession() == true;
  }

  String? getCurrentUserPublicKey() => _userPublicKey;
  String? getCurrentUsername() => _currentUsername;

  Future<void> _fetchCurrentUserInfo() async {
    try {
      final networkUsers = await getNetworkUsers();
      for (final user in networkUsers) {
        if (user.publicKey == _userPublicKey) {
          _currentUsername = user.name;
          return;
        }
      }
      _currentUsername = _userPublicKey != null && _userPublicKey!.length >= 8
          ? 'User_${_userPublicKey!.substring(0, 8)}'
          : 'User_Unknown';
    } catch (e) {
      _currentUsername = _userPublicKey != null && _userPublicKey!.length >= 8
          ? 'User_${_userPublicKey!.substring(0, 8)}'
          : 'User_Unknown';
    }
  }

  Timer? _pollingTimer;

  void startMessagePolling() {
    _stopMessagePolling();
    _pollingTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => receiveMessages());
  }

  void _stopMessagePolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('CommunicationManager not initialized.');
    }
  }

  void _ensureConnected() {
    if (!isConnected()) throw StateError('Not connected.');
  }

  @override
  void dispose() {
    _webSocketService.dispose();
    _webSocketSubscription?.cancel();
    _messageStreamController.close();
    _apiClient?.dispose();
    _stopMessagePolling();
    super.dispose();
  }
}

// ──────────────────────────────────────────────────────────
// RESULT / EXCEPTION CLASSES
// ──────────────────────────────────────────────────────────

class ConnectionResult {
  final bool success;
  final String? publicKey;
  final String? sessionId;
  final String? username;
  final String? errorMessage;

  ConnectionResult({
    required this.success,
    this.publicKey,
    this.sessionId,
    this.username,
    this.errorMessage,
  });

  ConnectionResult.failure(String error)
      : success = false,
        publicKey = null,
        sessionId = null,
        username = null,
        errorMessage = error;
}

class InitializationException implements Exception {
  final String message;
  InitializationException(this.message);

  @override
  String toString() => 'InitializationException: $message';
}