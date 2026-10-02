import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Préfixe des refus liés à la formule d'abonnement (voir triggers SQL).
const prefixeLimiteFormule = 'LIMITE_FORMULE:';

/// Affichage d'un refus de formule (renseigné au démarrage : propose de changer de formule).
void Function(BuildContext context, String message)? afficherLimiteFormule;

void snack(BuildContext context, String message, {bool erreur = false}) {
  final i = message.indexOf(prefixeLimiteFormule);
  if (i >= 0) {
    final texte = message.substring(i + prefixeLimiteFormule.length).trim();
    if (afficherLimiteFormule != null) {
      afficherLimiteFormule!(context, texte);
      return;
    }
    message = texte;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: erreur ? Colors.red.shade700 : null,
  ));
}

String messageErreur(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return _messageAuth(e);
  if (e is StorageException) return e.message;
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['erreur'] != null) return d['erreur'].toString();
    return 'Erreur du serveur (${e.status})';
  }
  return e.toString();
}

String _messageAuth(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('email not confirmed')) {
    return 'Adresse e-mail non confirmée : cliquez sur le lien reçu par e-mail, '
        'ou désactivez « Confirm email » dans Supabase.';
  }
  if (m.contains('invalid login credentials')) return 'E-mail ou mot de passe incorrect.';
  if (m.contains('already registered') || m.contains('already been registered')) {
    return 'Un compte existe déjà avec cet e-mail : connectez-vous.';
  }
  if (m.contains('rate limit') || e.statusCode == '429') {
    return 'Trop de tentatives ou d\'e-mails envoyés. Réessayez dans quelques minutes.';
  }
  if (m.contains('password')) return 'Mot de passe refusé : ${e.message}';
  if (m.contains('signups not allowed')) return 'Les inscriptions sont désactivées pour ce projet.';
  return e.message;
}

Future<bool> confirmer(BuildContext context, String titre, String message,
    {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titre),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Affiche un chargement, une erreur (avec « Réessayer ») ou le contenu.
class AsyncVue<T> extends StatelessWidget {
  const AsyncVue({
    super.key,
    required this.future,
    required this.builder,
    this.onReessayer,
    this.pleinEcran = false,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onReessayer;

  /// Écran complet : chargement et erreur sont affichés dans un Scaffold.
  final bool pleinEcran;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.done && !s.hasError) {
          return builder(context, s.data as T);
        }
        final contenu = _etat(s);
        return pleinEcran ? Scaffold(appBar: AppBar(), body: contenu) : contenu;
      },
    );
  }

  Widget _etat(AsyncSnapshot<T> s) {
    if (!s.hasError) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(messageErreur(s.error!), textAlign: TextAlign.center),
          if (onReessayer != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onReessayer, child: const Text('Réessayer')),
          ],
        ]),
      ),
    );
  }
}

class EtatVide extends StatelessWidget {
  const EtatVide({super.key, required this.icone, required this.message, this.action});

  final IconData icone;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class Section extends StatelessWidget {
  const Section({super.key, required this.titre, required this.children, this.action});

  final String titre;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(titre, style: Theme.of(context).textTheme.titleMedium)),
            if (action != null) action!,
          ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      ),
    );
  }
}

class Pastille extends StatelessWidget {
  const Pastille(this.texte, this.couleur, {super.key});

  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withAlpha(35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(texte,
          style: TextStyle(color: couleur, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Champ numérique (virgule ou point acceptés).
class ChampNombre extends StatelessWidget {
  const ChampNombre({
    super.key,
    required this.controller,
    required this.label,
    this.suffixe,
    this.obligatoire = false,
    this.aide,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? suffixe;
  final bool obligatoire;
  final String? aide;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: obligatoire ? '$label *' : label,
        suffixText: suffixe,
        helperText: aide,
        helperMaxLines: 2,
      ),
      validator: (v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return obligatoire ? 'Obligatoire' : null;
        final n = double.tryParse(t.replaceAll(' ', '').replaceAll(',', '.'));
        if (n == null) return 'Nombre invalide';
        if (n < 0) return 'Doit être positif';
        return null;
      },
    );
  }
}
