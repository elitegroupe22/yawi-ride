import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/alerts.dart';
import 'core/api.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'screens/auth/welcome.dart';
import 'screens/driver/driver_shell.dart';
import 'screens/passenger/passenger_shell.dart';
import 'widgets/ui.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  try {
    await Alerts.instance.init();
  } catch (e) {
    debugPrint('Notifications indisponibles : $e');
  }
  try {
    await Sonnerie.instance.init();
  } catch (_) {}

  final session = Session(Api());
  session.onSignedIn = () => Alerts.instance.register(session.api);
  session.onSigningOut = () => Alerts.instance.unregister();

  runApp(ChangeNotifierProvider.value(value: session, child: const YawiApp()));
  session.boot();
}

class YawiApp extends StatelessWidget {
  const YawiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yawi',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: yawiTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootGate(),
    );
  }
}

/// Aiguillage selon l'état de la session : chargement, visiteur, passager ou chauffeur.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: session.state == SessionState.loading || session.state == SessionState.guest
          ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (session.state) {
          SessionState.loading when session.bootError != null => Scaffold(
              key: const ValueKey('erreur'),
              body: RetryView(message: session.bootError!, onRetry: session.boot),
            ),
          SessionState.loading => const Splash(key: ValueKey('splash')),
          SessionState.guest => const WelcomeScreen(key: ValueKey('accueil')),
          SessionState.passenger => const PassengerShell(key: ValueKey('passager')),
          SessionState.driver => const DriverShell(key: ValueKey('chauffeur')),
        },
      ),
    );
  }
}

class Splash extends StatelessWidget {
  const Splash({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Y.nuit,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/images/mark.png', width: 96),
            const SizedBox(height: 28),
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Y.braiseClair)),
          ]),
        ),
      );
}
