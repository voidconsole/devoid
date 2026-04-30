import 'package:devoid/screens/users_screen.dart';
import 'package:devoid/screens/handshake_screen.dart';
import 'package:devoid/theme/app_colors.dart';
import 'package:devoid/widgets/squircle_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:devoid/main.dart';
import 'package:devoid/services/api_client.dart';
import 'package:devoid/services/auth_service.dart';
import 'package:devoid/services/crypto_service.dart';

class ConfirmationScreen extends StatefulWidget {
  final Map<String, dynamic>? metadata;
  final String? textCode;

  const ConfirmationScreen({Key? key, this.metadata, this.textCode})
      : super(key: key);

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  bool _isValid = false;
  bool _isVerifying = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCode();
    });
  }

  Future<void> _decryptCode(String code) async {
    const superSecretDecryptionKey = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
    List<String> codeList = code.substring(1, code.length - 1).split('');
    List<String> sha = [];
    List<String> base = [];
    int usedSha = 0;
    int usedBase = 0;

    try {
     // AYEEEE SLICK - this is some next level obfuscation right here, not even gonna lie
     // Can't show you this part of the code, it's too secret. Just know that it involves some very complex math and a sprinkle of magic. The decryption key is hidden in plain sight, but only the worthy can decipher it. If you're reading this, congrats, you made it this far. Now go forth and conquer the rest of the code!
     // However, if it did not hide it, the app would hardly be secure. 
      }

      String fingerprint = sha.join();
      String userKey = base.join();

      if (!mounted) return;

      setState(() {
        _isVerifying = true;
      });

      // Store credentials temporarily (not committed yet)
      final storage = CommManagerProvider.of(context, listen: false).storage;
      final serverAddress = 'look.who.came.to.hunt.my.ip';

      // Test connection with these credentials
      try {
        // Create temporary API client
        // Note: fingerprint is Ed25519 server key, not TLS cert
        // We accept self-signed TLS cert, security comes from Ed25519 auth
        final apiClient = ApiClient(
          serverAddress: serverAddress,
          pinnedFingerprint: fingerprint, // Stored for reference only
        );

        // Test server health (validates certificate)
        final healthResponse = await apiClient.get('/health');
        if (!healthResponse.isSuccess) {
          throw Exception('Server health check failed');
        }

        // Create crypto service and auth service
        final cryptoService = CryptoService();
        final authService = AuthService(
          apiClient: apiClient,
          cryptoService: cryptoService,
        );

        // Try to authenticate (this checks if user is in allowlist)
        final authResult = await authService.authenticate(userKey);

        if (!authResult.success) {
          // User not authorized (not in allowlist)
          if (mounted) {
            setState(() {
              _isValid = false;
              _isVerifying = false;
              _errorMessage = 'User not authorized. Contact admin for access.';
            });
          }

          // Show error and go back
          await Future.delayed(const Duration(seconds: 3));
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HandshakeScreen()),
                  (route) => false,
            );
          }
          return;
        }

        // Authentication successful! Store credentials permanently
        await storage.storeServerFingerprint(fingerprint);
        await storage.storeUserPrivateKey(userKey);
        await storage.storeServerAddress(serverAddress);

        print('✅ Credentials verified and stored');

        if (mounted) {
          setState(() {
            _isValid = true;
            _isVerifying = false;
          });
        }

        // Show success for 2 seconds
        await Future.delayed(const Duration(seconds: 2));

        // Navigate to users screen
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const UsersScreen()),
                (route) => false,
          );
        }

        // Cleanup
        apiClient.dispose();

      } on ApiException catch (e) {
        if (mounted) {
          setState(() {
            _isValid = false;
            _isVerifying = false;
            _errorMessage = 'Connection error: ${e.message}';
          });
        }

        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HandshakeScreen()),
                (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isValid = false;
            _isVerifying = false;
            _errorMessage = 'Verification failed: $e';
          });
        }

        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HandshakeScreen()),
                (route) => false,
          );
        }
      }
    } catch (e) {
      print('Error during decryption: $e');
      if (mounted) {
        setState(() {
          _isValid = false;
          _isVerifying = false;
          _errorMessage = 'Invalid handshake format';
        });

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HandshakeScreen()),
                  (route) => false,
            );
          }
        });
      }
    }
  }

  void _checkCode() {
    String? codeToDecrypt;

// Another secret part. Can't show you this one either, but let's just say it involves some very clever string manipulation and a dash of reverse engineering. 
    if (codeToDecrypt != null) {
      _decryptCode(codeToDecrypt);
    } else {
      setState(() {
        _isValid = false;
        _isVerifying = false;
        _errorMessage = 'Invalid handshake code';
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HandshakeScreen()),
                (route) => false,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Hero(
              tag: 'square',
              child: Container(
                width: 120,
                height: 120,
                padding: const EdgeInsets.all(30),
                decoration: ShapeDecoration(
                  color: primaryColor,
                  shape: SquircleBorder(radius: 24),
                ),
                child: _isVerifying
                    ? CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    scaffoldBackgroundColor,
                  ),
                  strokeWidth: 3,
                )
                    : _isValid
                    ? SvgPicture.asset('assets/icons/valid.svg')
                    : SvgPicture.asset('assets/icons/invalid.svg'),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              _isVerifying
                  ? "Verifying..."
                  : _isValid
                  ? "You're in."
                  : _errorMessage ?? "Invalid handshake.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: primaryColor,
                fontSize: 32,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (_isVerifying) ...[
              const SizedBox(height: 16),
              Text(
                'Checking authorization...',
                style: TextStyle(
                  color: primaryColor.withAlpha(128),
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
