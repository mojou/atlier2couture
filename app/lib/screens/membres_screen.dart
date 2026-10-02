import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Équipe de l'atelier : propriétaire, gérant, couturiers, caissiers.
class MembresScreen extends StatefulWidget {
  const MembresScreen({super.key});

  @override
  State<MembresScreen> createState() => _MembresScreenState();
}

class _MembresScreenState extends State<MembresScreen> {
  late Future<List<Map<String, dynamic>>> _f = _charger();

  Future<List<Map<String, dynamic>>> _charger() =>
      supa.from('membres').select().eq('atelier_id', Session.instance.atelierId).order('created_at');

  void _recharger() => setState(() => _f = _charger());

  Future<void> _ajouter() async {
    final email = TextEditingController();
    var role = 'couturier';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Ajouter un membre'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('La personne doit d\'abord créer son compte dans l\'application avec cet e-mail.'),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Rôle'),
              items: [
                for (final r in const ['gerant', 'couturier', 'caissier'])
                  DropdownMenuItem(value: r, child: Text(roles[r]!)),
              ],
              onChanged: (v) => setState(() => role = v ?? 'couturier'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    if (ok != true || email.text.trim().isEmpty) return;
    try {
      await supa.rpc('ajouter_membre', params: {
        'a': Session.instance.atelierId,
        'courriel': email.text.trim(),
        'r': role,
      });
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _changerRole(Map<String, dynamic> m, String role) async {
    try {
      await supa
          .from('membres')
          .update({'role': role})
          .eq('atelier_id', Session.instance.atelierId)
          .eq('user_id', m['user_id'] as String);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _retirer(Map<String, dynamic> m) async {
    if (!await confirmer(context, 'Retirer', 'Retirer ${m['nom']} de l\'atelier ?', ok: 'Retirer')) return;
    try {
      await supa
          .from('membres')
          .delete()
          .eq('atelier_id', Session.instance.atelierId)
          .eq('user_id', m['user_id'] as String);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gestion = Session.instance.estGestionnaire;
    return Scaffold(
      appBar: AppBar(title: const Text('Équipe')),
      floatingActionButton: gestion
          ? FloatingActionButton.extended(
              onPressed: _ajouter,
              icon: const Icon(Icons.person_add),
              label: const Text('Membre'),
            )
          : null,
      body: AsyncVue<List<Map<String, dynamic>>>(
        future: _f,
        onReessayer: _recharger,
        builder: (context, membres) => ListView(children: [
          for (final m in membres)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text('${m['nom'] ?? ''}${m['user_id'] == utilisateurId ? ' (vous)' : ''}'),
              subtitle: Text(roles[m['role']] ?? m['role'] as String),
              trailing: gestion && m['role'] != 'proprietaire' && m['user_id'] != utilisateurId
                  ? PopupMenuButton<String>(
                      onSelected: (v) => v == 'retirer' ? _retirer(m) : _changerRole(m, v),
                      itemBuilder: (_) => [
                        for (final r in const ['gerant', 'couturier', 'caissier'])
                          if (r != m['role']) PopupMenuItem(value: r, child: Text('Rôle : ${roles[r]}')),
                        const PopupMenuItem(value: 'retirer', child: Text('Retirer de l\'atelier')),
                      ],
                    )
                  : null,
            ),
        ]),
      ),
    );
  }
}
