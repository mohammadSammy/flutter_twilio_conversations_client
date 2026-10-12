import 'package:flutter/material.dart';

import 'src/connect_screen.dart';
import 'src/harness.dart';
import 'src/home_screen.dart';

/// The proof-of-concept harness (`flutter run -t lib/harness_app.dart`): every scenario in docs/poc-success-criteria.md can be
/// run from here. Tokens come from tool/token_server.py; see the example README.
void main() => runApp(HarnessScope(harness: Harness(), child: const ExampleApp()));

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final harness = HarnessScope.of(context);
    return MaterialApp(
      title: 'Twilio Conversations harness',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: harness.client == null ? const ConnectScreen() : const HomeScreen(),
    );
  }
}
