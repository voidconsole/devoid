import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:devoid/models/message.dart';
import 'package:devoid/models/network_user.dart';
import 'package:devoid/services/notification_service.dart';
import 'package:devoid/theme/app_colors.dart';
import 'package:devoid/widgets/custom_icon_button_shape.dart';
import 'package:devoid/widgets/message_bubble.dart';
import 'package:devoid/widgets/squircle_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:devoid/main.dart';
import 'package:mime/mime.dart';

/// Maximum file size the UI will accept (10 MB raw).
/// The server allows ~37 MB of encrypted payload (50 MB JSON limit,
/// base64 adds 33%), but keeping the client cap lower prevents
/// accidental huge uploads on slow connections.
const int _kMaxFileSizeBytes = 10 * 1024 * 1024;

class ChatScreen extends StatefulWidget {
  final NetworkUser user;

  const ChatScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late FocusNode _messageFocus;

  final List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  StreamSubscription? _messageSubscription;

  static const int _messagesPerPage = 50;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _messageFocus = FocusNode();

    NotificationService().requestPermissions();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = CommManagerProvider.of(context, listen: false);
      provider.commManager.setActiveChat(widget.user.publicKey);
      provider.commManager.clearUnread(widget.user.publicKey);
    });

    _loadConversation();
    _listenForMessages();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    final provider = CommManagerProvider.of(context, listen: false);
    provider.commManager.setActiveChat(null);

    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    _messageFocus.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────
  // SCROLL / PAGINATION
  // ──────────────────────────────────────────────────────────

  void _onScroll() {
    if (_scrollController.position.pixels <= 200 &&
        !_isLoadingMore &&
        _hasMoreMessages &&
        !_isLoading) {
      _loadMoreMessages();
    }
  }

  // ──────────────────────────────────────────────────────────
  // LOAD HISTORY
  // ──────────────────────────────────────────────────────────

  Future<void> _loadConversation() async {
    setState(() {
      _isLoading = true;
      _currentPage = 0;
    });

    try {
      final provider = CommManagerProvider.of(context, listen: false);
      final commManager = provider.commManager;

      final receivedMessages = await commManager.getConversation(
        otherPublicKey: widget.user.publicKey,
        limit: _messagesPerPage,
      );

      final currentUserKey = commManager.getCurrentUserPublicKey();

      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(
            receivedMessages.map((msg) => _receivedToMessage(msg, currentUserKey)),
          );
          _hasMoreMessages = receivedMessages.length == _messagesPerPage;
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Failed to load messages: $e');
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    try {
      final provider = CommManagerProvider.of(context, listen: false);
      final commManager = provider.commManager;

      _currentPage++;
      final offset = _currentPage * _messagesPerPage;

      final allMessages = await commManager.getConversation(
        otherPublicKey: widget.user.publicKey,
        limit: offset + _messagesPerPage,
      );

      final newMessages = allMessages.length > _messages.length
          ? allMessages.sublist(0, allMessages.length - _messages.length)
          : [];

      final currentUserKey = commManager.getCurrentUserPublicKey();

      if (mounted && newMessages.isNotEmpty) {
        final scrollOffset = _scrollController.offset;

        setState(() {
          _messages.insertAll(
            0,
            newMessages.map((msg) => _receivedToMessage(msg, currentUserKey)),
          );
          _hasMoreMessages = newMessages.length == _messagesPerPage;
          _isLoadingMore = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final newMax = _scrollController.position.maxScrollExtent;
            final target =
                newMax - (_scrollController.position.maxScrollExtent - scrollOffset);
            _scrollController.jumpTo(target.clamp(0.0, newMax));
          }
        });
      } else {
        setState(() {
          _hasMoreMessages = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  // ──────────────────────────────────────────────────────────
  // REAL-TIME MESSAGES
  // ──────────────────────────────────────────────────────────

  void _listenForMessages() {
    final provider = CommManagerProvider.of(context, listen: false);
    final commManager = provider.commManager;

    _messageSubscription = commManager.messageStream.listen((received) {
      if (received.from == widget.user.publicKey) {
        if (mounted) {
          setState(() {
            _messages.add(_receivedToMessage(
                received, commManager.getCurrentUserPublicKey()));
          });
          _scrollToBottom();
        }
      }
    });
  }

  // ──────────────────────────────────────────────────────────
  // SEND TEXT
  // ──────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) {
      _messageFocus.requestFocus();
      return;
    }

    final messageText = _messageController.text.trim();
    _messageController.clear();
    setState(() => _isSending = true);
    _messageFocus.requestFocus();

    try {
      final provider = CommManagerProvider.of(context, listen: false);
      final commManager = provider.commManager;

      final result = await commManager.sendMessage(
        recipientPublicKey: widget.user.publicKey,
        message: messageText,
      );

      if (result.success) {
        if (mounted) {
          setState(() {
            _messages.add(Message(
              text: messageText,
              isUser: true,
              timestamp: result.timestamp,
              type: 'text',
            ));
          });
          _scrollToBottom();
        }
      } else {
        _showError('Failed to send message: ${result.error}');
      }
    } catch (e) {
      _showError('Error sending message: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _messageFocus.requestFocus();
      }
    }
  }

  // ──────────────────────────────────────────────────────────
  // SEND MEDIA
  // ──────────────────────────────────────────────────────────

  /// Opens the system file picker, enforces the size cap, then encrypts
  /// and sends the file using the same AES-GCM path as text.
  Future<void> _pickAndSendMedia() async {
    if (_isSending) return;

    try {
      // Pick any file type — images, videos, docs, everything
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true, // load bytes in memory directly
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final Uint8List? fileBytes = picked.bytes;

      if (fileBytes == null) {
        _showError('Could not read file. Try again.');
        return;
      }

      if (fileBytes.length > _kMaxFileSizeBytes) {
        _showError(
          'File is too large (${(fileBytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Maximum is 10 MB.',
        );
        return;
      }

      final fileName = picked.name;
      final mimeType =
          lookupMimeType(fileName) ?? 'application/octet-stream';

      // Determine type category
      final String type;
      if (mimeType.startsWith('image/')) {
        type = 'image';
      } else if (mimeType.startsWith('video/')) {
        type = 'video';
      } else {
        type = 'file';
      }

      setState(() => _isSending = true);

      final provider = CommManagerProvider.of(context, listen: false);
      final commManager = provider.commManager;

      final sendResult = await commManager.sendMedia(
        recipientPublicKey: widget.user.publicKey,
        fileBytes: fileBytes,
        mimeType: mimeType,
        fileName: fileName,
        type: type,
      );

      if (sendResult.success) {
        if (mounted) {
          setState(() {
            _messages.add(Message(
              isUser: true,
              timestamp: sendResult.timestamp,
              type: type,
              mediaBytes: fileBytes,
              mimeType: mimeType,
              fileName: fileName,
            ));
          });
          _scrollToBottom();
        }
      } else {
        _showError('Failed to send file: ${sendResult.error}');
      }
    } catch (e) {
      _showError('Error sending file: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ──────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────

  Message _receivedToMessage(dynamic msg, String? currentUserKey) {
    // Works with ReceivedMessage from message_service.dart
    return Message(
      text: msg.type == 'text' ? msg.plaintext : null,
      isUser: msg.from == currentUserKey,
      timestamp: msg.timestamp,
      type: msg.type ?? 'text',
      mediaBytes: msg.mediaBytes,
      mimeType: msg.mimeType,
      fileName: msg.fileName,
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scaffoldBackgroundColor,
        elevation: 0,
        toolbarHeight: 80,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Container(
                width: 30,
                height: 30,
                decoration: ShapeDecoration(
                  color: primaryColor,
                  shape: SquircleBorder(radius: 14),
                ),
                child: Container(
                  alignment: Alignment.center,
                    child: Text(
                    widget.user.icon,
                    style: TextStyle(
                      color: scaffoldBackgroundColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            Container(
              padding: const EdgeInsets.only(right: 15),
                child: Text(
                  widget.user.name,
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isLoading)
                  LinearProgressIndicator(
                backgroundColor: scaffoldBackgroundColor,
                valueColor:
                    AlwaysStoppedAnimation<Color>(primaryColor),
              )
            else
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet\nSend a message to start the conversation',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryColor.withAlpha(128),
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(20),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isPreviousFromSame = index > 0 &&
                              _messages[index - 1].isUser == message.isUser;
                          return MessageBubble(
                            message: message,
                            isPreviousMessageFromSameUser: isPreviousFromSame,
                          );
                        },
                      ),
              ),

            // ── Input bar ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Text field
                  Expanded(
                    child: Container(
                      decoration: ShapeDecoration(
                        shape: SquircleBorder(
                          side: BorderSide(
                            color: primaryColor.withAlpha(77),
                          ),
                          radius: 20,
                        ),
                        color: primaryColor.withAlpha(5),
                      ),
                      child: TextField(
                        focusNode: _messageFocus,
                        controller: _messageController,
                        onSubmitted: (_) => _sendMessage(),
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: _isSending
                              ? 'Encrypting…'
                              : 'Send a message',
                          hintStyle: TextStyle(
                            color: primaryColor.withAlpha(77),
                            fontSize: 16,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          suffixIcon: GestureDetector(
                            onTap: _isSending ? null : _pickAndSendMedia,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Transform.rotate(
                                angle: 0.5235987756, // 30 degrees in radians
                                child: Icon(
                                  Icons.attach_file,
                                  color: _isSending
                                      ? primaryColor.withAlpha(50)
                                      : primaryColor.withAlpha(179),
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Send button
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: ShapeDecoration(
                        color: _isSending
                            ? primaryColor.withAlpha(30)
                            : primaryColor,
                        shape: CustomIconButtonShape(
                               side: BorderSide(
                                 color: scaffoldBackgroundColor,
                                 width: 2,
                               ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(10, 12, 13, 12),
                      child: _isSending
                          ? SvgPicture.asset(
                              'assets/icons/send.svg',
                              colorFilter: ColorFilter.mode(
                                primaryColor.withAlpha(180),
                                BlendMode.srcIn,
                              ),
                            )
                          : SvgPicture.asset(
                              'assets/icons/send.svg',
                                  colorFilter: ColorFilter.mode(
                                scaffoldBackgroundColor,
                                BlendMode.srcIn,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}