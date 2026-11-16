import 'package:flutter/material.dart';

import 'src/core/emulator.dart';
import 'src/ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Emulator.instance.init();
  runApp(const AltirraApp());
}

class AltirraApp extends StatelessWidget {
  const AltirraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THE Atari 800',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE67E22),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
