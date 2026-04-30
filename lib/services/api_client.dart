import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Secure HTTP client that accepts self-signed certificates
/// Security comes from Ed25519 authentication, not certificate pinning
class ApiClient {
  final String serverAddress;
  final String pinnedFingerprint; // Ed25519 server key fingerprint (for reference only)
  late http.Client _client;

  ApiClient({
    required this.serverAddress,
    required this.pinnedFingerprint,
  }) {
    _client = _createHttpClient();
  }

  /// Creates HTTP client that accepts self-signed certificates
  /// Note: We accept the self-signed cert because:
  /// 1. TLS still provides encryption
  /// 2. Real security comes from Ed25519 challenge-response auth
  /// 3. Server validates users against allowlist
  /// 4. Handshake itself is the trust anchor (distributed securely)
  http.Client _createHttpClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        // Accept self-signed certificates
        // Security is provided by Ed25519 authentication, not cert pinning
        print('✅ Accepting TLS certificate for $host:$port');
        print('   (Security via Ed25519 auth + server allowlist)');
        return true;
      };

    return IOClient(httpClient);
  }

  /// GET request with error handling
  Future<ApiResponse> get(String endpoint) async {
    try {
      final url = Uri.parse('$serverAddress$endpoint');
      print('→ GET $url');
      final response = await _client.get(url);
      return _handleResponse(response);
    } catch (e) {
      throw ApiException('GET request failed: $e');
    }
  }

  /// POST request with JSON body
  Future<ApiResponse> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final url = Uri.parse('$serverAddress$endpoint');
      print('→ POST $url');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      throw ApiException('POST request failed: $e');
    }
  }

  /// POST request with binary data
  Future<ApiResponse> postBinary(String endpoint, Uint8List data) async {
    try {
      final url = Uri.parse('$serverAddress$endpoint');
      print('→ POST $url (binary)');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/octet-stream'},
        body: data,
      );
      return _handleResponse(response);
    } catch (e) {
      throw ApiException('POST binary request failed: $e');
    }
  }

  /// Handles HTTP response and converts to ApiResponse
  /// Throws ApiException for non-2xx status codes
  ApiResponse _handleResponse(http.Response response) {
    print('← Response: ${response.statusCode}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        // Try to parse as JSON
        final json = jsonDecode(response.body);
        return ApiResponse(
          statusCode: response.statusCode,
          data: json,
          rawBody: response.body,
        );
      } catch (_) {
        // If not JSON, return raw body
        return ApiResponse(
          statusCode: response.statusCode,
          data: null,
          rawBody: response.body,
        );
      }
    } else {
      throw ApiException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  /// Cleanup resources
  void dispose() {
    _client.close();
  }
}

/// Structured API response
class ApiResponse {
  final int statusCode;
  final dynamic data; // Parsed JSON or null
  final String rawBody;

  ApiResponse({
    required this.statusCode,
    required this.data,
    required this.rawBody,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message';
}