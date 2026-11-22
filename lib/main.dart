import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/student_home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/news_detail_screen.dart';
import 'models/event_model.dart';
import 'models/news_model.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ✅ ВКЛЮЧАЕМ КЭШИРОВАНИЕ (экономит десятки тысяч чтений)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Firebase init error: $e');
    runApp(const _InitErrorApp());
    return;
  }

  await _initOptionalServices();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CampusApp());
}

Future<void> _initOptionalServices() async {
  try {
    await Supabase.initialize(
      url: 'https://nuioftskrpglkuzthylz.supabase.co',
      anonKey: 'sb_publishable_JS4T9X637rNcaD5FKeddyw_018lwRuW',
    );
  } catch (e) { debugPrint('Supabase init error: $e'); }

  try {
    await SettingsService.instance.loadSettings();
  } catch (e) { debugPrint('Settings load error: $e'); }

  try {
    await NotificationService.initialize();
  } catch (e) { debugPrint('Notification init error: $e'); }

  try {
    if (kDebugMode) OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize("dca38e09-702f-4808-95e4-ecbb2213dfd1");

    if (SettingsService.instance.notificationsEnabled) {
      OneSignal.User.pushSubscription.optIn();
    } else {
      OneSignal.User.pushSubscription.optOut();
    }

    OneSignal.Notifications.addClickListener((event) async {
      final data = event.notification.additionalData;
      if (data == null) return;
      final type = data['type'] as String?;
      final targetId = data['targetId'] as String?;
      if (type == null || targetId == null || targetId.isEmpty) return;

      final nav = navigatorKey.currentState;
      if (nav == null) return;

      try {
        if (type == 'event') {
          final doc = await FirebaseFirestore.instance.collection('events').doc(targetId).get();
          if (!doc.exists) return;
          final ev = Event.fromMap(doc.id, doc.data()!);
          nav.push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: ev)));
        } else if (type == 'news') {
          final doc = await FirebaseFirestore.instance.collection('news').doc(targetId).get();
          if (!doc.exists) return;
          final nw = News.fromMap(doc.data()!, doc.id);
          nav.push(MaterialPageRoute(builder: (_) => NewsDetailScreen(news: nw)));
        }
      } catch (e) { debugPrint('Push navigation error: $e'); }
    });
  } catch (e) { debugPrint('OneSignal init error: $e'); }
}

class _InitErrorApp extends StatelessWidget {
  const _InitErrorApp();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 56),
                SizedBox(height: 16),
                Text('Не удалось запустить приложение', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text('Проверьте подключение к интернету и откройте приложение снова.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Kampus-IT NEFU',
          navigatorKey: navigatorKey,
          theme: AppTheme.theme,
          darkTheme: AppTheme.darkTheme,
          themeMode: SettingsService.instance.themeMode,
          locale: SettingsService.instance.locale,
          supportedLocales: const [Locale('ru'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          debugShowCheckedModeBanner: false,
          home: const AuthWrapper(),
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Не удалось проверить вход. Попробуйте ещё раз.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Попробовать снова')),
                ],
              ),
            ),
          );
        }
        final user = snapshot.data;
        if (user == null) return const SplashScreen();
        if (!user.emailVerified) {
          return VerifyEmailScreen(onVerified: () { if (mounted) setState(() {}); });
        }
        return const _AppEntry();
      },
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry();
  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_completed') ?? false;
    if (mounted) setState(() => _onboardingDone = done);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_onboardingDone == false) {
      return OnboardingScreen(onCompleted: () { setState(() { _onboardingDone = true; }); });
    }
    return const StudentHomeScreen();
  }
}