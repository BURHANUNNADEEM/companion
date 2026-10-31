import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_config.dart';
import 'l10n/strings.dart';
import 'screens/caregiver_home_screen.dart';
import 'screens/consent_screen.dart';
import 'screens/parent_home_screen.dart';
import 'screens/role_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/api_client.dart';
import 'services/app_state.dart';
import 'services/auth_service.dart';
import 'services/contacts_store.dart';
import 'services/navigation_service.dart';
import 'services/scam_input_service.dart';
import 'services/services.dart';
import 'services/tier2_bridge.dart';
import 'services/voice_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isDevAuth) {
    await Firebase.initializeApp(); // uses android/app/google-services.json
  }
  final auth = AuthService();
  await auth.init();
  final contacts = ContactsStore();
  final api = ApiClient(AppConfig.apiBaseUrl, auth.idToken);
  final state = AppState(api: api, contacts: contacts);
  await state.loadLocal();
  final services = AppServices(
    api: api,
    auth: auth,
    nav: NavigationService(contacts),
    tier2: Tier2Bridge(),
    voice: VoiceService(),
    scamInput: ScamInputService(),
  );
  runApp(MultiProvider(
    providers: [
      Provider<AppServices>.value(value: services),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<AppState>.value(value: state),
    ],
    child: const CompanionApp(),
  ));
}

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'Companion',
      debugShowCheckedModeBanner: false,
      locale: Locale(state.lang),
      supportedLocales: const [Locale('ur'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.build(state.lang),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = state.bigText ? 1.3 : 1.0;
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: state.isUrdu ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        );
      },
      home: const AppRoot(),
    );
  }
}

/// Routes: sign in -> role (once) -> consent (once) -> parent home | caregiver home.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final state = context.watch<AppState>();
    final s = S.of(context);

    if (!auth.signedIn) {
      _requested = false;
      if (state.me != null) WidgetsBinding.instance.addPostFrameCallback((_) => state.clearUser());
      return const SignInScreen();
    }
    if (state.me == null) {
      if (!_requested && !state.loadingMe) {
        _requested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => state.refreshMe());
      }
      if (state.error != null && !state.loadingMe) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off_rounded, size: 72),
                const SizedBox(height: 12),
                Text(state.error == 'offline' ? s.t('error_offline') : s.t('error_generic'), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: state.refreshMe, child: Text(s.t('retry'))),
                TextButton(onPressed: auth.signOut, child: Text(s.t('sign_out'))),
              ]),
            ),
          ),
        );
      }
      return Scaffold(body: Center(child: Text(s.t('loading'))));
    }
    if (state.role == null) return const RoleScreen();
    if (!state.consentDone) return const ConsentScreen();
    return state.role == 'caregiver' ? const CaregiverHomeScreen() : const ParentHomeScreen();
  }
}
