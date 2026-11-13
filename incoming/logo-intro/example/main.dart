import 'package:flutter/material.dart';
import '../logo_intro.dart'; // in your app: import 'package:your_app/logo_intro/logo_intro.dart';

void main() => runApp(const MaterialApp(home: Demo()));

class Demo extends StatefulWidget {
  const Demo({super.key});
  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  final intro = LogoIntroController();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3EFE9),
    body: Center(
      child: LogoIntro(
        size: MediaQuery.of(context).size.width * .9,
        controller: intro,
        onFinished: () => debugPrint('intro finished'),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: intro.replay,
      icon: const Icon(Icons.replay),
      label: const Text('Replay'),
    ),
  );
}
