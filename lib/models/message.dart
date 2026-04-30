import 'dart:typed_data';

/// Represents a single message in the chat UI.
/// Supports text, image, video, and arbitrary file attachments.
class Message {
  /// Plain text content. Non-null for type == 'text'.
  final String? text;

  /// Whether this message was sent by the current user.
  final bool isUser;

  /// When the message was sent / received.
  final DateTime timestamp;

  /// 'text' | 'image' | 'video' | 'file'
  final String type;

  /// Decoded binary content for media messages.
  /// Null for text messages.
  final Uint8List? mediaBytes;

  /// MIME type, e.g. 'image/jpeg', 'video/mp4', 'application/pdf'.
  /// Non-null for media messages.
  final String? mimeType;

  /// Original filename. Non-null for video and file messages.
  final String? fileName;

  const Message({
    this.text,
    required this.isUser,
    required this.timestamp,
    this.type = 'text',
    this.mediaBytes,
    this.mimeType,
    this.fileName,
  });

  bool get isMedia => type != 'text';
  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';
  bool get isFile => type == 'file';
}