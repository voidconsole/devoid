import 'package:devoid/screens/handshake_screen.dart';
import 'package:devoid/screens/users_screen.dart';
import 'package:devoid/theme/app_colors.dart';
import 'package:devoid/widgets/squircle_border.dart';
import 'package:flutter/material.dart';
import 'package:devoid/main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Give splash screen time to display
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final provider = CommManagerProvider.of(context);
    final storage = provider.storage;

    // Check if user has credentials
    final hasCredentials = await storage.hasUserCredentials();
    final hasServerConfig = await storage.hasServerConfig();

    if (hasCredentials && hasServerConfig) {
      // User has completed handshake, go to users screen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const UsersScreen()),
        );
      }
    } else {
      // First time user, show handshake screen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HandshakeScreen()),
        );
      }
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
                width: 80,
                height: 80,
                decoration: ShapeDecoration(
                  color: primaryColor,
                  shape: SquircleBorder(radius: 40),
                ),
              ),
            ),
            const SizedBox(height: 60),
            Text(
              'devoid',
              style: TextStyle(
                color: primaryColor,
                fontSize: 48,
                fontWeight: FontWeight.w500,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
