import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/call_screen.dart';
import 'screens/friends_screen.dart';

void main() {
  runApp(const CipherApp());
}

class CipherApp extends StatelessWidget {
  const CipherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cipher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF5865F2),
        scaffoldBackgroundColor: const Color(0xFF202225),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5865F2),
          secondary: Color(0xFF00A884),
          surface: Color(0xFF2F3136),
          // ponytail: fix DEAD-3 — 'background' removed (deprecated in Flutter 3.18+)
        ),
        fontFamily: 'Inter',
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
        '/qr_scanner': (context) => const QRScannerScreen(),
        '/friends': (context) => const FriendsScreen(),
      },
      // Call screen uses onGenerateRoute to pass arguments
      onGenerateRoute: (settings) {
        if (settings.name == '/call') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => CallScreen(
              peer: args['peer'] as String,
              callType: args['callType'] as String? ?? 'voice',
              callId: args['callId'] as String?,
              isIncoming: args['isIncoming'] as bool? ?? false,
            ),
          );
        }
        return null;
      },
    );
  }
}
