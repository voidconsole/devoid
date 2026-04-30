import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket service for real-time message push notifications
class WebSocketService {
  WebSocketChannel? _channel;
  String? _serverAddress;
  String? _userPublicKey;
  bool _isConnected = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _isConnecting = false;

  // Stream controller for incoming messages
  final StreamController<Map<String, dynamic>> _messageController =
  StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  bool get isConnected => _isConnected;

  /// Connects to WebSocket server
  Future<void> connect({
    required String serverAddress,
    required String userPublicKey,
  }) async {
    if (_isConnected || _isConnecting) {
      return;
    }

    _isConnecting = true;
    _serverAddress = serverAddress;
    _userPublicKey = userPublicKey;

    try {
      // Convert HTTPS URL to WSS URL
      final wsUrl = serverAddress
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');

      print('🔌 Connecting to WebSocket: $wsUrl');

      // Manual connection via HttpClient to handle self-signed certificates
      final wsUri = Uri.parse(wsUrl);
      
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      final websocket = await WebSocket.connect(
        wsUrl,
        customClient: httpClient,
      ).timeout(const Duration(seconds: 10));

      _channel = IOWebSocketChannel(websocket);

      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: true,
      );

      // Authenticate
      _authenticate();

      _isConnected = true;
      _isConnecting = false;
      _startPingTimer();

      print('✅ WebSocket connected');
    } catch (e) {
      print('❌ WebSocket connection failed: $e');
      _isConnecting = false;
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  /// Authenticates the WebSocket connection
  void _authenticate() {
    if (_channel == null || _userPublicKey == null) return;

    try {
      final authMessage = json.encode({
        'type': 'auth',
        'publicKey': _userPublicKey,
      });

      _channel!.sink.add(authMessage);
      print('🔐 WebSocket authentication sent');
    } catch (e) {
      print('❌ Failed to send WebSocket auth: $e');
    }
  }

  /// Handles incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'auth_success':
          print('✅ WebSocket authenticated');
          break;

        case 'auth_failed':
          print('❌ WebSocket authentication failed: ${data['message']}');
          disconnect();
          break;

        case 'new_message':
          final messageData = data['message'] as Map<String, dynamic>;
          print('📬 New message received via WebSocket');
          _messageController.add(messageData);
          break;

        case 'pong':
          // Keepalive response
          break;

        default:
          print('⚠️ Unknown WebSocket message type: $type');
      }
    } catch (e) {
      print('❌ Error handling WebSocket message: $e');
    }
  }

  /// Handles WebSocket errors
  void _handleError(error) {
    print('❌ WebSocket error: $error');
    _isConnected = false;
    _isConnecting = false;
    _scheduleReconnect();
  }

  /// Handles WebSocket disconnect
  void _handleDone() {
    print('🔌 WebSocket stream closed');
    _isConnected = false;
    _isConnecting = false;
    _stopPingTimer();
    _scheduleReconnect();
  }

  /// Starts ping timer for keepalive
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendPing();
    });
  }

  /// Stops ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Sends ping to keep connection alive
  void _sendPing() {
    if (_channel == null || !_isConnected) return;

    try {
      _channel!.sink.add(json.encode({'type': 'ping'}));
    } catch (e) {
      print('❌ Failed to send ping: $e');
    }
  }

  /// Schedules automatic reconnection
  void _scheduleReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return;
    }

    // Only reconnect if we haven't explicitly disconnected
    if (_serverAddress == null) return;

    print('⏰ Scheduling WebSocket reconnect in 5 seconds...');

    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected && !_isConnecting && _serverAddress != null && _userPublicKey != null) {
        print('🔄 Attempting to reconnect WebSocket...');
        connect(
          serverAddress: _serverAddress!,
          userPublicKey: _userPublicKey!,
        );
      }
    });
  }

  /// Disconnects from WebSocket
  Future<void> disconnect() async {
    print('🔌 Disconnecting WebSocket...');

    _stopPingTimer();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final channelToClose = _channel;
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _serverAddress = null;
    _userPublicKey = null;

    if (channelToClose != null) {
      try {
        // Use a timeout to prevent hanging on close
        await channelToClose.sink.close().timeout(
          const Duration(seconds: 2),
          onTimeout: () => print('⚠️ WebSocket sink close timed out'),
        );
      } catch (e) {
        print('⚠️ Error closing WebSocket sink: $e');
      }
    }

    print('✅ WebSocket disconnected');
  }

  /// Cleanup resources
  void dispose() {
    disconnect();
    _messageController.close();
  }
}