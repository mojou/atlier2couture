import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'conversation_screen.dart';

/// Ouvre la discussion interne d'une commande (créée au premier accès).
Future<void> ouvrirDiscussionCommande(BuildContext context, Map<String, dynamic> commande) async {
  try {
    final id = await supa.rpc('conversation_commande', params: {'cmd': commande['id']}) as String;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationScreen(
        conversationId: id,
        titre: 'Commande ${commande['numero'] ?? ''}',
        sousTitre: (commande['clients'] as Map?)?['nom'] as String?,
      ),
    ));
  } catch (e) {
    if (context.mounted) snack(context, messageErreur(e), erreur: true);
  }
}

/// Messagerie interne de l'atelier : canaux, messages privés, discussions de commandes.
class MessagerieScreen extends StatefulWidget {
  const MessagerieScreen({super.key});

  @override
  State<MessagerieScreen> createState() => _MessagerieScreenState();
}

class _MessagerieScreenState extends State<MessagerieScreen> {
  late Future<List<Map<String, dynamic>>> _f = _charger();
  RealtimeChannel? _canal;
  Timer? _rafraichir;

  @override
  void initState() {
    super.initState();
    // Un nouveau message (n'importe quelle conversation visible) rafraîchit la liste.
    _canal = supa
        .channel('messagerie-${Session.instance.atelierId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'atelier_id',
            value: Session.instance.atelierId,
          ),
          callback: (_) {
            _rafraichir?.cancel();
            _rafraichir = Timer(const Duration(milliseconds: 600), () {
              if (mounted) _recharger();
            });
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _rafraichir?.cancel();
    if (_canal != null) supa.removeChannel(_canal!);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final a = Session.instance.atelierId;
    await supa.rpc('messagerie_initialiser', params: {'a': a});
    final r = await supa.rpc('messagerie_liste', params: {'a': a});
    return [for (final e in r as List) Map<String, dynamic>.from(e as Map)];
  }

  void _recharger() => setState(() => _f = _charger());

  String _titre(Map<String, dynamic> c) => switch (c['type']) {
        'canal' => '# ${c['nom']}',
        'direct' => (c['autre_nom'] as String?) ?? 'Conversation privée',
        _ => 'Commande ${c['commande_numero'] ?? ''}',
      };

  Future<void> _ouvrir(Map<String, dynamic> c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationScreen(
        conversationId: c['id'] as String,
        titre: _titre(c),
        sousTitre: switch (c['type']) {
          'canal' => 'Canal de l\'atelier',
          'direct' => 'Message privé',
          _ => c['client_nom'] as String?,
        },
      ),
    ));
    if (mounted) _recharger();
  }

  Future<void> _nouveau() async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Message privé'),
            subtitle: const Text('Écrire à un membre de l\'équipe'),
            onTap: () => Navigator.pop(c, 'direct'),
          ),
          if (Session.instance.estGestionnaire)
            ListTile(
              leading: const Icon(Icons.tag),
              title: const Text('Nouveau canal'),
              subtitle: const Text('Ex. : Découpe, Livraisons, Boutique 2…'),
              onTap: () => Navigator.pop(c, 'canal'),
            ),
        ]),
      ),
    );
    if (!mounted || choix == null) return;
    if (choix == 'direct') {
      await _messagePrive();
    } else {
      await _nouveauCanal();
    }
  }

  Future<void> _messagePrive() async {
    try {
      final membres = await supa
          .from('membres')
          .select('user_id, nom, role')
          .eq('atelier_id', Session.instance.atelierId)
          .neq('user_id', utilisateurId!)
          .order('nom');
      if (!mounted) return;
      if (membres.isEmpty) {
        snack(context, 'Aucun autre membre dans l\'atelier. Ajoutez votre équipe depuis Plus → Équipe.');
        return;
      }
      final m = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            for (final x in membres)
              ListTile(
                leading: CircleAvatar(child: Text(((x['nom'] as String?) ?? '?').characters.first.toUpperCase())),
                title: Text(x['nom'] as String? ?? ''),
                subtitle: Text(roles[x['role']] ?? ''),
                onTap: () => Navigator.pop(c, x),
              ),
          ]),
        ),
      );
      if (m == null || !mounted) return;
      final id = await supa.rpc('conversation_directe',
          params: {'a': Session.instance.atelierId, 'autre': m['user_id']}) as String;
      if (!mounted) return;
      await _ouvrir({'id': id, 'type': 'direct', 'autre_nom': m['nom']});
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _nouveauCanal() async {
    final nom = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nouveau canal'),
        content: TextField(
          controller: nom,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom du canal', hintText: 'ex. Découpe'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Créer')),
        ],
      ),
    );
    if (ok != true || nom.text.trim().isEmpty) return;
    try {
      final id = await supa.rpc('creer_canal', params: {'a': Session.instance.atelierId, 'n': nom.text.trim()}) as String;
      if (!mounted) return;
      await _ouvrir({'id': id, 'type': 'canal', 'nom': nom.text.trim()});
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _supprimerCanal(Map<String, dynamic> c) async {
    if (!await confirmer(context, 'Supprimer le canal', 'Supprimer « ${c['nom']} » et tous ses messages ?',
        ok: 'Supprimer')) {
      return;
    }
    try {
      await supa.from('conversations').delete().eq('id', c['id'] as String);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Widget _avatar(Map<String, dynamic> c) {
    final t = Theme.of(context);
    return switch (c['type']) {
      'canal' => CircleAvatar(
          backgroundColor: t.colorScheme.primaryContainer,
          child: Icon(Icons.tag, color: t.colorScheme.onPrimaryContainer),
        ),
      'direct' => CircleAvatar(
          child: Text(((c['autre_nom'] as String?) ?? '?').characters.first.toUpperCase()),
        ),
      _ => CircleAvatar(
          backgroundColor: Colors.amber.shade100,
          child: const Icon(Icons.receipt_long, color: Colors.brown),
        ),
    };
  }

  String _heureCourte(DateTime d) {
    final j = DateTime(d.year, d.month, d.day);
    if (j == aujourdhui()) return heure(d);
    return dateCourte(d).substring(0, 5);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Messagerie')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nouveau,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Nouveau'),
      ),
      body: AsyncVue<List<Map<String, dynamic>>>(
        future: _f,
        onReessayer: _recharger,
        builder: (context, conversations) => RefreshIndicator(
          onRefresh: () async => _recharger(),
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: conversations.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final c = conversations[i];
              final nonLus = (c['non_lus'] as num?)?.toInt() ?? 0;
              final dernier = lireDate(c['dernier_le']);
              final apercu = c['dernier_message'] == null
                  ? (c['type'] == 'canal' ? 'Canal de toute l\'équipe' : 'Aucun message')
                  : '${c['dernier_auteur'] ?? ''} : ${c['dernier_message']}';
              final supprimable =
                  c['type'] == 'canal' && c['nom'] != 'Général' && Session.instance.estGestionnaire;
              return ListTile(
                leading: _avatar(c),
                title: Text(_titre(c),
                    style: TextStyle(fontWeight: nonLus > 0 ? FontWeight.bold : FontWeight.w500)),
                subtitle: Text(
                  [if (c['type'] == 'commande' && c['client_nom'] != null) c['client_nom'], apercu].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: nonLus > 0 ? FontWeight.w600 : null),
                ),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (dernier != null) Text(_heureCourte(dernier), style: t.textTheme.labelSmall),
                  const SizedBox(height: 4),
                  if (nonLus > 0)
                    Badge(label: Text('$nonLus'), backgroundColor: t.colorScheme.primary)
                  else if (supprimable)
                    InkWell(
                      onTap: () => _supprimerCanal(c),
                      child: Icon(Icons.delete_outline, size: 18, color: t.colorScheme.outline),
                    ),
                ]),
                onTap: () => _ouvrir(c),
              );
            },
          ),
        ),
      ),
    );
  }
}
