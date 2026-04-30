import 'dart:async';
import 'package:devoid/models/network_user.dart';
import 'package:devoid/screens/chat_screen.dart';
import 'package:devoid/screens/handshake_screen.dart';
import 'package:devoid/theme/app_colors.dart';
import 'package:devoid/widgets/network_tile.dart';
import 'package:devoid/widgets/squircle_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:devoid/main.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({Key? key}) : super(key: key);

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool _isConnecting = true;
  bool _isConnected = false;
  String? _errorMessage;
  String? _currentUserPublicKey;
  String? _currentUsername;
  List<NetworkUser> _networkUsers = [];
  bool _isLoadingUsers = false;
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAndConnect();
    _listenForMessages();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _listenForMessages() {
    final provider = CommManagerProvider.of(context, listen: false);
    final commManager = provider.commManager;

    _messageSubscription = commManager.messageStream.listen((message) {
      // Force UI update when new message arrives
      if (mounted) {
        setState(() {
          // Re-sort users list to put unread at top
          _sortUsersList();
        });
      }
    });
  }

  void _sortUsersList() {
    final provider = CommManagerProvider.of(context, listen: false);
    final commManager = provider.commManager;

    // Sort: unread users first, then alphabetically
    _networkUsers.sort((a, b) {
      final aUnread = commManager.hasUnreadFrom(a.publicKey);
      final bUnread = commManager.hasUnreadFrom(b.publicKey);

      if (aUnread && !bUnread) return -1;
      if (!aUnread && bUnread) return 1;

      return a.name.compareTo(b.name);
    });
  }

  Future<void> _initializeAndConnect() async {
    final provider = CommManagerProvider.of(context, listen: false);
    final commManager = provider.commManager;

    try {
      await commManager.initialize();
      final result = await commManager.connect();

      if (result.success) {
        if (mounted) {
          setState(() {
            _isConnected = true;
            _isConnecting = false;
            _currentUserPublicKey = result.publicKey;
            _currentUsername = result.username;
          });
        }
        await _fetchNetworkUsers();
      } else {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _isConnecting = false;
            _errorMessage = result.errorMessage ?? 'Connection failed';
          });
          _showErrorDialog(result.errorMessage ?? 'Failed to connect to server');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
          _errorMessage = e.toString();
        });
        _showErrorDialog('Initialization error: $e');
      }
    }
  }

  Future<void> _fetchNetworkUsers() async {
    if (mounted) setState(() => _isLoadingUsers = true);

    try {
      final provider = CommManagerProvider.of(context, listen: false);
      final commManager = provider.commManager;
      final networkUsers = await commManager.getNetworkUsers();

      final filteredUsers = networkUsers
          .where((user) => user.publicKey != _currentUserPublicKey)
          .toList();

      if (mounted) {
        setState(() {
          _networkUsers = filteredUsers;
          _sortUsersList();
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load network users: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: primaryColor.withAlpha(77)),
        ),
        title: Text('Connection Error', style: TextStyle(color: primaryColor)),
        content: Text(message, style: TextStyle(color: primaryColor.withAlpha(179))),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _isConnecting = true);
              _initializeAndConnect();
            },
            child: Text('Retry', style: TextStyle(color: primaryColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: primaryColor.withAlpha(128))),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeHandshake() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: primaryColor.withAlpha(77)),
        ),
        title: Text('Revoke Handshake', style: TextStyle(color: primaryColor)),
        content: Text(
          'This will log you out and clear all credentials. You will need a new handshake to reconnect.',
          style: TextStyle(color: primaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: primaryColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final provider = CommManagerProvider.of(context, listen: false);
      await provider.commManager.logout();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HandshakeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final commManager = CommManagerProvider.of(context).commManager;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 80,
        automaticallyImplyLeading: false,
        titleSpacing: 27,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Hero(
              tag: 'square',
              child: GestureDetector(
                onTap: () {
                  isDarkMode.value = !isDarkMode.value;
                },
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: ShapeDecoration(
                    color: primaryColor,
                    shape: SquircleBorder(radius: 15),
                  ),
                ),
              ),
            ),
            Text(
              'devoid',
              style: TextStyle(
                color: primaryColor,
                fontSize: 30,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(child: _isConnecting
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
            const SizedBox(height: 24),
            Text('Connecting to nexus...', style: TextStyle(color: primaryColor, fontSize: 16)),
          ],
        ),
      )
          : ListenableBuilder(
        listenable: commManager,
        builder: (context, _) {
          return Column(
            children: [
              if (!_isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: Colors.red.withOpacity(0.1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Disconnected - ${_errorMessage ?? "Unknown error"}',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 30),
              Expanded(
                child: _isLoadingUsers
                    ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                )
                    : _networkUsers.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: primaryColor.withAlpha(77)),
                      const SizedBox(height: 16),
                      Text(
                        'No other users on the network',
                        style: TextStyle(color: primaryColor.withAlpha(128), fontSize: 16),
                      ),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _fetchNetworkUsers,
                  color: primaryColor,
                  child: ListView.builder(
                    itemCount: _networkUsers.length,
                    itemBuilder: (context, index) {
                      final user = _networkUsers[index];
                      final isUnread = commManager.hasUnreadFrom(user.publicKey);
                      return NetworkTile(
                        icon: user.icon,
                        name: user.name,
                        isUnread: isUnread,
                        onTap: () {
                          if (!_isConnected) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cannot chat while disconnected'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(user: user),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return Stack(
                                  children: [
                                    Container(color: scaffoldBackgroundColor),
                                    FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  ],
                                );
                              },
                              transitionDuration: const Duration(milliseconds: 200),
                            ),
                          ).then((_) {
                            // Re-sort after coming back from chat
                            if (mounted) {
                              setState(() {
                                _sortUsersList();
                              });
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: primaryColor.withAlpha(26))),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: ShapeDecoration(
                            color: primaryColor,
                            shape: SquircleBorder(radius: 20),
                          ),
                          child: Center(
                            child: Text(
                              _currentUsername != null && _currentUsername!.isNotEmpty
                                  ? _currentUsername!.substring(0, 1)
                                  : 'N',
                              style: TextStyle(color: scaffoldBackgroundColor, fontSize: 40, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('You', style: TextStyle(color: primaryColor.withAlpha(128), fontSize: 16)),
                              Text(
                                _currentUsername ?? 'Nautical',
                                style: TextStyle(color: primaryColor, fontSize: 16, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ListTile(
                      leading: SvgPicture.asset(
                        'assets/icons/revoke.svg',
                        colorFilter: ColorFilter.mode(primaryColor.withAlpha(179), BlendMode.srcIn),
                      ),
                      onTap: _revokeHandshake,
                      title: Text(
                        'Revoke handshake',
                        style: TextStyle(color: primaryColor.withAlpha(179), fontSize: 18),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),),
    );
  }
}