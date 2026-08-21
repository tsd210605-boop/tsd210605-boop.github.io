import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'screens/chat_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()..loadInitialData()),
      ],
      child: const TaxMateApp(),
    ),
  );
}

class TaxMateApp extends StatelessWidget {
  const TaxMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaxMate AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2B5B84), // Primary Blue from design
          primary: const Color(0xFF2B5B84),
          surface: const Color(0xFFF4F7FB), // Very light blue/gray background
        ),
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
        useMaterial3: true,
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name != null && settings.name!.startsWith('/chat/')) {
          final sessionId = settings.name!.replaceFirst('/chat/', '');
          return MaterialPageRoute(
            builder: (context) => ChatScreen(sessionId: sessionId),
          );
        }
        return MaterialPageRoute(
          builder: (context) => const ChatScreen(),
        );
      },
    );
  }
}

