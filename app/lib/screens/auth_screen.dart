import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/config.dart';

import '../core/supa.dart';
import '../core/widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _mdp = TextEditingController();
  final _nom = TextEditingController();
  bool _inscription = false;
  bool _occupe = false;
  bool _masque = true;

  Future<void> _valider() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _occupe = true);
    try {
      if (_inscription) {
        final r = await supa.auth.signUp(
          email: _email.text.trim(),
          password: _mdp.text,
          data: {'nom': _nom.text.trim()},
        );
        if (r.session == null && mounted) {
          snack(context, 'Compte créé. Confirmez votre adresse e-mail puis connectez-vous.');
          setState(() => _inscription = false);
        }
      } else {
        await supa.auth.signInWithPassword(email: _email.text.trim(), password: _mdp.text);
      }
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  /// Page ouverte par le lien de l'e-mail : l'application web en cours si on est
  /// dans un navigateur, sinon l'adresse publique configurée (SITE_URL).
  String? _adresseRetour() {
    if (kIsWeb) {
      final b = Uri.base;
      return Uri(scheme: b.scheme, host: b.host, port: b.hasPort ? b.port : null, path: b.path).toString();
    }
    return Config.siteUrl.isEmpty ? null : Config.siteUrl;
  }

  Future<void> _motDePasseOublie() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      snack(context, 'Saisissez d\'abord votre adresse e-mail', erreur: true);
      return;
    }
    try {
      await supa.auth.resetPasswordForEmail(email, redirectTo: _adresseRetour());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_outlined, size: 40),
          title: const Text('Vérifiez vos e-mails'),
          content: Text('Si un compte existe pour $email, un e-mail contenant un lien de réinitialisation '
              'vient d\'être envoyé.\n\nOuvrez-le, cliquez sur le lien puis choisissez votre nouveau mot de passe. '
              'Pensez à regarder dans les courriers indésirables (spam).'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.content_cut, size: 64, color: t.colorScheme.primary),
                const SizedBox(height: 12),
                Text('Atelier Couture', textAlign: TextAlign.center, style: t.textTheme.headlineMedium),
                Text('Commandes, coupe, stock, factures et rendez-vous',
                    textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
                const SizedBox(height: 32),
                if (_inscription) ...[
                  TextFormField(
                    controller: _nom,
                    decoration: const InputDecoration(labelText: 'Nom complet', prefixIcon: Icon(Icons.person)),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email)),
                  validator: (v) => (v ?? '').contains('@') ? null : 'E-mail invalide',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mdp,
                  obscureText: _masque,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_masque ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _masque = !_masque),
                    ),
                  ),
                  validator: (v) => (v ?? '').length < 6 ? '6 caractères minimum' : null,
                  onFieldSubmitted: (_) => _valider(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _occupe ? null : _valider,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _occupe
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_inscription ? 'Créer mon compte' : 'Se connecter'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _inscription = !_inscription),
                  child: Text(_inscription ? 'J\'ai déjà un compte' : 'Créer un compte'),
                ),
                if (!_inscription)
                  TextButton(onPressed: _motDePasseOublie, child: const Text('Mot de passe oublié ?')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
