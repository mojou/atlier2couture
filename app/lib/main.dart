import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import 'core/config.dart';
import 'core/session.dart';
import 'core/supa.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'screens/abonnement_screen.dart';
import 'screens/atelier_gate.dart';
import 'screens/auth_screen.dart';
import 'screens/nouveau_mot_de_passe_screen.dart';
import 'services/alarmes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR');
  if (Config.estConfigure) {
    // Lien « mot de passe oublié » ouvert dans le navigateur : on le repère avant
    // que Supabase ne consomme le jeton contenu dans l'adresse.
    if (kIsWeb && Uri.base.fragment.contains('type=recovery')) enRecuperation.value = true;
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabasePublishableKey,
      // Flux « implicite » : le lien de réinitialisation fonctionne quel que soit
      // l'appareil ou le navigateur qui l'ouvre (le flux PKCE exige le même navigateur).
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    supa.auth.onAuthStateChange.listen((e) {
      if (e.event == AuthChangeEvent.passwordRecovery) enRecuperation.value = true;
    });
    await Alarmes.init();
  }
  afficherLimiteFormule = proposerFormule;
  runApp(const CoutureApp());
}

class CoutureApp extends StatelessWidget {
  const CoutureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Atelier Couture',
        debugShowCheckedModeBanner: false,
        theme: construireTheme(Session.instance.couleur),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Config.estConfigure ? const AuthGate() : const _ConfigManquante(),
      ),
    );
  }
}

/// Vrai quand l'utilisateur arrive par un lien « mot de passe oublié » :
/// on lui demande son nouveau mot de passe avant d'ouvrir l'application.
final enRecuperation = ValueNotifier<bool>(false);

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supa.auth.onAuthStateChange,
      builder: (context, _) {
        final session = supa.auth.currentSession;
        if (session == null) return const AuthScreen();
        return ValueListenableBuilder<bool>(
          valueListenable: enRecuperation,
          builder: (context, recuperation, _) => recuperation
              ? NouveauMotDePasseScreen(onTermine: () => enRecuperation.value = false)
              : AtelierGate(key: ValueKey(session.user.id)),
        );
      },
    );
  }
}

class _ConfigManquante extends StatelessWidget {
  const _ConfigManquante();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Connexion Supabase non configurée.\n\nLancez l\'application avec :\n'
            'flutter run --dart-define-from-file=config.json',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
