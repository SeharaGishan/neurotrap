import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const NeuroTrapApp());
}

class NeuroTrapApp extends StatelessWidget {
  const NeuroTrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroTrap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
        ),
        useMaterial3: true,
      ),
      home: const TestScreen(),
    );
  }
}

class TestScreen extends StatelessWidget {
  const TestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.security,
              color: Color(0xFF00E5FF),
              size: 80,
            ),
            const SizedBox(height: 24),
            const Text(
              'NEUROTRAP',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Security That Evolves',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 14,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 48),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF00E5FF),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '✅ Firebase Connected',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}