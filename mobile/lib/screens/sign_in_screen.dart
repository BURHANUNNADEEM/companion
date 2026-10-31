import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/auth_service.dart';
import '../widgets/language_toggle.dart';

/// Firebase phone-OTP or email login (F5). Dev mode: a demo user id (backend AUTH_MODE=dev).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _devUid = TextEditingController(text: 'demo-parent');
  bool _usePhone = true;
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      setState(() => _error = S.read(context).t('error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final auth = context.read<AuthService>();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Align(child: LanguageToggle()),
            const SizedBox(height: 28),
            const Icon(Icons.favorite_rounded, size: 80, color: Color(0xFF0B5D3B)),
            const SizedBox(height: 12),
            Text(s.t('welcome'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            Text(s.t('welcome_sub'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 28),
            if (auth.devMode) ...[
              TextField(controller: _devUid, decoration: InputDecoration(labelText: s.t('dev_user'))),
              const SizedBox(height: 12),
              TextField(controller: _email, decoration: InputDecoration(labelText: s.t('email'))),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _busy ? null : () => _run(() => auth.devSignIn(_devUid.text, email: _email.text)),
                child: Text(s.t('sign_in')),
              ),
            ] else if (_usePhone) ...[
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.t('phone'), hintText: s.t('phone_hint')),
              ),
              const SizedBox(height: 12),
              if (_codeSent)
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: s.t('enter_code')),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          if (!_codeSent) {
                            await auth.sendPhoneCode(_phone.text);
                            setState(() => _codeSent = true);
                          } else {
                            await auth.verifyPhoneCode(_code.text);
                          }
                        }),
                child: Text(_codeSent ? s.t('verify') : s.t('send_code')),
              ),
              TextButton(onPressed: () => setState(() => _usePhone = false), child: Text(s.t('use_email'))),
            ] else ...[
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: s.t('email'))),
              const SizedBox(height: 12),
              TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: s.t('password'))),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _busy ? null : () => _run(() => auth.emailSignIn(_email.text, _password.text)),
                child: Text(s.t('sign_in')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(() => auth.emailSignIn(_email.text, _password.text, create: true)),
                child: Text(s.t('create_account')),
              ),
              TextButton(onPressed: () => setState(() => _usePhone = true), child: Text(s.t('use_phone'))),
            ],
            if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 20)),
          ],
        ),
      ),
    );
  }
}
