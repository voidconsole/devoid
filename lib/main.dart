import 'package:flutter/material.dart';
import 'package:devoid/screens/splash_screen.dart';
import 'package:devoid/services/communication_manager.dart';
import 'package:devoid/services/secure_storage_service.dart';
import 'package:devoid/services/notification_service.dart';
import 'package:devoid/theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Initialize storage service
  final storage = SecureStorageService();

  // Initialize communication manager (but don't connect yet)
  final commManager = CommunicationManager(
    storage: storage,
    notificationService: notificationService,
  );

  runApp(DevoidApp(
    commManager: commManager,
    storage: storage,
  ));
}

class DevoidApp extends StatelessWidget {
  final CommunicationManager commManager;
  final SecureStorageService storage;

  const DevoidApp({
    Key? key,
    required this.commManager,
    required this.storage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CommManagerProvider(
      commManager: commManager,
      storage: storage,
      child: ValueListenableBuilder<bool>(
        valueListenable: isDarkMode,
        builder: (context, dark, _) {
          return MaterialApp(
            title: 'devoid',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              textSelectionTheme: TextSelectionThemeData(
                selectionColor: primaryColor.withAlpha(20),
                cursorColor: primaryColor.withAlpha(77),
                selectionHandleColor: primaryColor.withAlpha(77),
              ),
              scaffoldBackgroundColor: scaffoldBackgroundColor,
              fontFamily: 'Uber Move',
              canvasColor: scaffoldBackgroundColor,
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: BlackFadeTransitionBuilder(),
                  TargetPlatform.iOS: BlackFadeTransitionBuilder(),
                },
              ),
            ),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

/// Custom page transition builder for smooth black fade transitions
class BlackFadeTransitionBuilder extends PageTransitionsBuilder {
  const BlackFadeTransitionBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
      ) {
    return Stack(
      children: [
        // Black background during transition
        Container(color: scaffoldBackgroundColor),
        // Fade transition
        FadeTransition(
          opacity: animation,
          child: child,
        ),
      ],
    );
  }
}

/// Provider to pass services down the widget tree
class CommManagerProvider extends InheritedWidget {
  final CommunicationManager commManager;
  final SecureStorageService storage;

  const CommManagerProvider({
    Key? key,
    required this.commManager,
    required this.storage,
    required Widget child,
  }) : super(key: key, child: child);

  static CommManagerProvider of(BuildContext context, {bool listen = true}) {
    final CommManagerProvider? provider = listen
        ? context.dependOnInheritedWidgetOfExactType<CommManagerProvider>()
        : context.getInheritedWidgetOfExactType<CommManagerProvider>();

    if (provider == null) {
      throw StateError('CommManagerProvider not found in widget tree');
    }
    return provider;
  }

  @override
  bool updateShouldNotify(CommManagerProvider oldWidget) => false;
}