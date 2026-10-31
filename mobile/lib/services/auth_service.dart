import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';

/// Firebase Authentication (phone OTP or email) - PRD F5.
/// In AUTH_MODE=dev (demo/testing without Firebase) a local demo id is used and sent as `dev:<uid>:<email>`.
class AuthService extends ChangeNotifier {
  AuthService({this.devMode = AppConfig.isDevAuth});

  final bool devMode;
  String? _devUid;
  String? _devEmail;
  String? _verificationId;

  bool get signedIn => devMode ? _devUid != null : FirebaseAuth.instance.currentUser != null;

  Future<void> init() async {
    if (devMode) {
      final p = await SharedPreferences.getInstance();
      _devUid = p.getString('dev_uid');
      _devEmail = p.getString('dev_email');
    } else {
      FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
    }
    notifyListeners();
  }

  Future<String?> idToken() async {
    if (devMode) {
      if (_devUid == null) return null;
      return _devEmail == null ? 'dev:$_devUid' : 'dev:$_devUid:$_devEmail';
    }
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  Future<void> devSignIn(String uid, {String? email}) async {
    final p = await SharedPreferences.getInstance();
    _devUid = uid.trim();
    _devEmail = (email ?? '').trim().isEmpty ? null : email!.trim().toLowerCase();
    await p.setString('dev_uid', _devUid!);
    if (_devEmail != null) await p.setString('dev_email', _devEmail!);
    notifyListeners();
  }

  Future<void> emailSignIn(String email, String password, {bool create = false}) async {
    if (create) {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.trim(), password: password);
    } else {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.trim(), password: password);
    }
  }

  /// Sends the SMS code. For the demo use Firebase *test phone numbers* (no real SMS / billing needed).
  Future<void> sendPhoneCode(String phone) async {
    final done = Completer<void>();
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone.trim(),
      verificationCompleted: (cred) async {
        await FirebaseAuth.instance.signInWithCredential(cred); // Android auto-retrieval
        if (!done.isCompleted) done.complete();
      },
      verificationFailed: (e) {
        if (!done.isCompleted) done.completeError(e);
      },
      codeSent: (id, _) {
        _verificationId = id;
        if (!done.isCompleted) done.complete();
      },
      codeAutoRetrievalTimeout: (id) => _verificationId = id,
    );
    return done.future;
  }

  Future<void> verifyPhoneCode(String code) async {
    final id = _verificationId;
    if (id == null) throw StateError('no_verification');
    await FirebaseAuth.instance.signInWithCredential(
      PhoneAuthProvider.credential(verificationId: id, smsCode: code.trim()),
    );
  }

  Future<void> signOut() async {
    if (devMode) {
      final p = await SharedPreferences.getInstance();
      await p.remove('dev_uid');
      await p.remove('dev_email');
      _devUid = null;
      _devEmail = null;
    } else {
      await FirebaseAuth.instance.signOut();
    }
    notifyListeners();
  }
}
