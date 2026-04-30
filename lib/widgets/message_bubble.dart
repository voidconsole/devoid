import 'dart:io';
import 'dart:typed_data';
import 'package:devoid/models/message.dart';
import 'package:devoid/theme/app_colors.dart';
import 'package:devoid/widgets/message_bubble_border.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

/// Renders a single chat bubble.
///
/// Supports four content types, all using the existing [MessageBubbleBorder]
/// tail shape so the design language stays consistent:
///   • text  – original behaviour, unchanged
///   • image – bubble-clipped thumbnail, tappable for full-screen viewer
///   • video – icon + filename + size, tappable to open with system player
///   • file  – icon + filename + size, tappable to open with system handler
class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isPreviousMessageFromSameUser;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isPreviousMessageFromSameUser,
  }) : super(key: key);

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _isOpening = false;

  bool get isUser => widget.message.isUser;

  // ──────────────────────────────────────────────────────────
  // ACTIONS
  // ──────────────────────────────────────────────────────────

  /// Full-screen pinch-zoom viewer for images.
  void _viewImageFullScreen() {
    final bytes = widget.message.mediaBytes;
    if (bytes == null) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, animation, __) => _FullScreenImageViewer(
          bytes: bytes,
          fileName: widget.message.fileName,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  /// Writes the bytes to a temp file and opens with the OS default handler.
  Future<void> _openMediaFile() async {
    final bytes = widget.message.mediaBytes;
    if (bytes == null) return;

    setState(() => _isOpening = true);
    try {
      final dir = await getTemporaryDirectory();
      final safeName = _safeTempName(widget.message.fileName);
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes);

      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done && mounted) {
        _showError('Could not open file: ${result.message}');
      }
    } catch (e) {
      if (mounted) _showError('Error opening file: $e');
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ──────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;

    Widget content;
    if (msg.isImage && msg.mediaBytes != null) {
      content = _buildImageContent(msg.mediaBytes!);
    } else if (msg.isVideo || msg.isFile) {
      content = _buildFileContent(msg);
    } else {
      content = _buildTextContent(msg.text ?? '');
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: widget.isPreviousMessageFromSameUser ? 4 : 16,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: content,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // CONTENT BUILDERS
  // ──────────────────────────────────────────────────────────

  /// Plain text bubble — identical to the original widget.
  Widget _buildTextContent(String text) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: isUser ? Colors.transparent : primaryColor,
        shape: MessageBubbleBorder(
          isUser: !isUser,
          side: BorderSide(
            color: isUser ? const Color(0xFF5D5D5D) : Colors.transparent,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: isUser
            ? const EdgeInsets.fromLTRB(28, 12, 18, 12)
            : const EdgeInsets.fromLTRB(18, 12, 28, 12),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? primaryColor : scaffoldBackgroundColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  /// Image bubble: thumbnail clipped with the bubble tail, tap to fullscreen.
  Widget _buildImageContent(Uint8List bytes) {
    return GestureDetector(
      onTap: _viewImageFullScreen,
      child: ClipPath(
        clipper: _BubbleClipper(isUser: !isUser),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 120,
            maxHeight: 260,
          ),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 160,
              height: 120,
              color: primaryColor.withAlpha(20),
              child: Center(
                child: Icon(Icons.broken_image, color: primaryColor, size: 40),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Video / file bubble: icon + name + size, tap to open with OS handler.
  Widget _buildFileContent(Message msg) {
    final IconData icon =
        msg.isVideo ? Icons.play_circle_fill : Icons.insert_drive_file;
    final String label =
        msg.fileName ?? (msg.isVideo ? 'Video' : 'File');
    final String sizeStr = _formatSize(msg.mediaBytes?.length);
    final Color fg = isUser ? primaryColor : scaffoldBackgroundColor;

    return GestureDetector(
      onTap: _isOpening ? null : _openMediaFile,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: isUser ? Colors.transparent : primaryColor,
          shape: MessageBubbleBorder(
            isUser: !isUser,
            side: BorderSide(
              color: isUser ? const Color(0xFF5D5D5D) : Colors.transparent,
              width: 1,
            ),
          ),
        ),
        child: Padding(
          padding: isUser
              ? const EdgeInsets.fromLTRB(28, 12, 18, 12)
              : const EdgeInsets.fromLTRB(18, 12, 28, 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon or progress spinner
              SizedBox(
                width: 40,
                height: 40,
                child: _isOpening
                    ? Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(fg),
                          ),
                        ),
                      )
                    : Icon(icon, color: fg, size: 36),
              ),
              const SizedBox(width: 10),
              // Filename + human-readable size
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    if (sizeStr.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _isOpening ? 'Opening…' : sizeStr,
                        style: TextStyle(
                          color: fg.withAlpha(153),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────

  String _safeTempName(String? rawName) {
    if (rawName == null || rawName.isEmpty) {
      return 'devoid_${DateTime.now().millisecondsSinceEpoch}';
    }
    return rawName.split('/').last.split('\\').last;
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes == 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ──────────────────────────────────────────────────────────
// CLIPPER — adapts MessageBubbleBorder path for ClipPath
// ──────────────────────────────────────────────────────────

class _BubbleClipper extends CustomClipper<Path> {
  final bool isUser;

  const _BubbleClipper({required this.isUser});

  @override
  Path getClip(Size size) {
    return MessageBubbleBorder(isUser: isUser)
        .getOuterPath(Offset.zero & size);
  }

  @override
  bool shouldReclip(_BubbleClipper old) => old.isUser != isUser;
}

// ──────────────────────────────────────────────────────────
// FULL-SCREEN IMAGE VIEWER
// ──────────────────────────────────────────────────────────

class _FullScreenImageViewer extends StatelessWidget {
  final Uint8List bytes;
  final String? fileName;

  const _FullScreenImageViewer({required this.bytes, this.fileName});

  Future<void> _openWith(BuildContext context) async {
    try {
      final dir = await getTemporaryDirectory();
      final name = (fileName != null && fileName!.isNotEmpty)
          ? fileName!
          : 'devoid_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          fileName ?? 'Image',
          style: const TextStyle(color: Colors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new, color: Colors.white),
            tooltip: 'Open with',
            onPressed: () => _openWith(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.memory(
            bytes,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}