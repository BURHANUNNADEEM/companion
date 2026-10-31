import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static bool _gsiReady = false;

  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _loading = true; _error = null; });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } on GoogleSignInException catch (e) {
      // user closing the Google sheet isn't an error worth showing
      if (e.code != GoogleSignInExceptionCode.canceled) {
        setState(() => _error = e.description ?? e.code.name);
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _emailAuth({required bool signUp}) => _run(() async {
        final auth = FirebaseAuth.instance;
        final email = _email.text.trim();
        if (signUp) {
          await auth.createUserWithEmailAndPassword(email: email, password: _password.text);
        } else {
          await auth.signInWithEmailAndPassword(email: email, password: _password.text);
        }
      });

  Future<void> _google() => _run(() async {
        if (!_gsiReady) {
          await GoogleSignIn.instance.initialize();
          _gsiReady = true;
        }
        final account = await GoogleSignIn.instance.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) throw Exception('Google did not return an ID token');
        await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : () => _emailAuth(signUp: false),
                child: const Text('Sign in'),
              ),
              TextButton(
                onPressed: _loading ? null : () => _emailAuth(signUp: true),
                child: const Text('Create account'),
              ),
              const Divider(height: 32),
              OutlinedButton.icon(
                onPressed: _loading ? null : _google,
                icon: const Icon(Icons.login),
                label: const Text('Continue with Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}