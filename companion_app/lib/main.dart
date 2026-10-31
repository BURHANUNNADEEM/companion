import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_globals.dart';
import 'companion/companion.dart';
import 'config.dart';
import 'firebase_options.dart';
import 'pages/bank_practice_pages.dart';
import 'pages/call_pages.dart';
import 'pages/consent_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/progress_page.dart';
import 'pages/scam_page.dart';
import 'pages/settings_help_pages.dart';
import 'pages/settings_page.dart';
import 'pages/whatsapp_pages.dart';
import 'services/backend_sync.dart';
import 'ui/guidance_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  companion = await CompanionController.create(
    helper: const Contact('son', helperNameUr, helperNameEn, helperPhone),
    config: CompanionConfig.demo, // fast thresholds for a live demo
  );
  backend = BackendSync(companion);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        textTheme: ThemeData.light().textTheme.apply(fontSizeFactor: 1.15),
        appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 21, color: Colors.black87)),
      ),
      navigatorObservers: [CompanionRouteObserver(companion)],
      initialRoute: '/',
      routes: {
        '/': (_) => const AuthGate(),
        Screens.contacts: (_) => const ContactsPage(),
        Screens.confirmCall: (_) => const ConfirmCallPage(),
        Screens.waContacts: (_) => const WaContactsPage(),
        Screens.waChatPractice: (_) => const WaChatPracticePage(),
        Screens.scamCheck: (_) => const ScamCheckPage(),
        Screens.settingsMenu: (_) => const SettingsMenuPage(),
        Screens.settingsLesson: (_) => const SettingsLessonPage(),
        Screens.bankPractice: (_) => const BankPracticePage(),
        Screens.bankOtp: (_) => const BankOtpPage(),
        '/progress': (_) => const ProgressPage(),
        '/settings': (_) => const SettingsPage(),
      },
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl, // Urdu first
        child: Stack(
          children: [
            child!,
            const Positioned.fill(child: GuidanceOverlay()),
          ],
        ),
      ),
    );
  }
}

/// Login (existing Firebase flow) → consent (first time) → home.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData) return const LoginPage();
        return ListenableBuilder(
          listenable: companion,
          builder: (context, _) => companion.needsConsent ? const ConsentPage() : const HomePage(),
        );
      },
    );
  }
}
