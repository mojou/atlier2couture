import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../core/supa.dart';
import '../core/widgets.dart';

/// Affiché après un clic sur le lien « mot de passe oublié » reçu par e-mail :
/// l'utilisateur est connecté temporairement et choisit son nouveau mot de passe.
class NouveauMotDePasseScreen extends StatefulWidget {
  const NouveauMotDePasseScreen({super.key, required this.onTermine});

  final VoidCallback onTermine;

  @override
  State<NouveauMotDePasseScreen> createState() => _NouveauMotDePasseScreenState();
}

class _NouveauMotDePasseScreenState extends State<NouveauMotDePasseScreen> {
  final _form = GlobalKey<FormState>();
  final _mdp = TextEditingController();
  final _confirmation = TextEditingController();
  bool _masque = true;
  bool _occupe = false;

  Future<void> _valider() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _occupe = true);
    try {
      await supa.auth.updateUser(UserAttributes(password: _mdp.text));
      if (!mounted) return;
      snack(context, 'Mot de passe modifié. Vous êtes connecté.');
      widget.onTermine();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final email = supa.auth.currentUser?.email ?? '';
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.lock_reset, size: 64, color: t.colorScheme.primary),
                const SizedBox(height: 12),
                Text('Nouveau mot de passe', textAlign: TextAlign.center, style: t.textTheme.headlineSmall),
                if (email.isNotEmpty)
                  Text('Compte : $email', textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _mdp,
                  obscureText: _masque,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_masque ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _masque = !_masque),
                    ),
                  ),
                  validator: (v) => (v ?? '').length < 6 ? '6 caractères minimum' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmation,
                  obscureText: _masque,
                  decoration: const InputDecoration(labelText: 'Confirmer le mot de passe', prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) => v != _mdp.text ? 'Les deux mots de passe sont différents' : null,
                  onFieldSubmitted: (_) => _valider(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _occupe ? null : _valider,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _occupe
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enregistrer le mot de passe'),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    widget.onTermine();
                    await supa.auth.signOut();
                  },
                  child: const Text('Annuler'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
