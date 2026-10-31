import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../api.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _result = 'Tap the button to call /api/me';

  Future<void> _callMe() async {
    try {
      final res = await apiGet('/api/me');
      setState(() => _result = '${res.statusCode}: ${res.body}');
    } catch (e) {
      setState(() => _result = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Companion'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signed in as ${user?.email}'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _callMe, child: const Text('Call /api/me')),
            const SizedBox(height: 16),
            Text(_result),
          ],
        ),
      ),
    );
  }
}