import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/core/theme/mantra_matrix_theme.dart';
import 'package:mantra_matrix/features/auth/presentation/screens/auth_gate.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ProviderScope(child: AstaMatrixApp()));
}

class AstaMatrixApp extends StatelessWidget {
  const AstaMatrixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asta Matrix',
      debugShowCheckedModeBanner: false,
      theme: MantraMatrixTheme.light,
      darkTheme: MantraMatrixTheme.dark,
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}
