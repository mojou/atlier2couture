import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

const _modesPaie = {'aucun': 'Non payé à la tâche', 'piece': 'À la pièce', 'pourcentage': '% du prix de façon'};

class _Ligne {
  _Ligne(this.membre);

  final Map<String, dynamic> membre;
  final commandes = <String>[];
  int vetements = 0;
  double facon = 0;
  double paye = 0;

  String get userId => membre['user_id'] as String;
  String get nom => (membre['nom'] as String?) ?? '';
  String get mode => (membre['paie_mode'] as String?) ?? 'aucun';
  double get valeur => num0(membre['paie_valeur']);

  double get du => switch (mode) {
        'piece' => vetements * valeur,
        'pourcentage' => facon * valeur / 100,
        _ => 0,
      };

  double get reste => du - paye;
}

/// Paie des couturiers : vêtements terminés dans le mois (passage à « Prête »)
/// par couturier assigné, montant dû selon son tarif, versements enregistrés en dépenses.
class PaieScreen extends StatefulWidget {
  const PaieScreen({super.key});

  @override
  State<PaieScreen> createState() => _PaieScreenState();
}

class _PaieScreenState extends State<PaieScreen> {
  DateTime _mois = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<_Ligne>> _f = _charger();

  String get _periode => DateFormat('yyyy-MM').format(_mois);

  Future<List<_Ligne>> _charger() async {
    final a = Session.instance.atelierId;
    final debut = _mois.toUtc().toIso8601String();
    final fin = DateTime(_mois.year, _mois.month + 1).toUtc().toIso8601String();
    final r = await Future.wait<List<Map<String, dynamic>>>([
      supa.from('membres').select().eq('atelier_id', a).neq('role', 'proprietaire').order('nom'),
      supa
          .from('commande_historique')
          .select('commande_id, created_at, commandes(numero, statut, assigne_a, articles)')
          .eq('atelier_id', a)
          .eq('statut', 'prete')
          .gte('created_at', debut)
          .lt('created_at', fin),
      supa.from('depenses').select('membre_id, montant').eq('atelier_id', a).eq('categorie', 'salaire').eq('periode', _periode),
    ]);

    final lignes = {for (final m in r[0]) m['user_id'] as String: _Ligne(m)};
    final vues = <String>{};
    for (final h in r[1]) {
      final c = h['commandes'] as Map?;
      final id = h['commande_id'] as String;
      if (c == null || c['statut'] == 'annulee' || !vues.add(id)) continue;
      final l = lignes[c['assigne_a']];
      if (l == null) continue;
      l.commandes.add(c['numero'] as String? ?? '');
      for (final art in (c['articles'] as List? ?? const [])) {
        final q = ((art as Map)['quantite'] as num?)?.toInt() ?? 1;
        l.vetements += q;
        l.facon += q * num0(art['prix_facon']);
      }
    }
    for (final p in r[2]) {
      lignes[p['membre_id']]?.paye += num0(p['montant']);
    }
    return lignes.values.toList();
  }

  void _recharger() => setState(() => _f = _charger());

  void _changerMois(int delta) {
    _mois = DateTime(_mois.year, _mois.month + delta);
    _recharger();
  }

  Future<void> _tarif(_Ligne l) async {
    var mode = l.mode;
    final valeur = TextEditingController(text: nombreChamp(l.valeur));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: Text('Tarif de ${l.nom}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in _modesPaie.entries)
                ChoiceChip(label: Text(e.value), selected: mode == e.key, onSelected: (_) => setState(() => mode = e.key)),
            ]),
            if (mode != 'aucun') ...[
              const SizedBox(height: 12),
              ChampNombre(
                controller: valeur,
                label: mode == 'piece' ? 'Montant par vêtement' : 'Pourcentage du prix de façon',
                suffixe: mode == 'piece' ? Session.instance.devise : '%',
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await supa
          .from('membres')
          .update({'paie_mode': mode, 'paie_valeur': mode == 'aucun' ? 0 : (lireNombre(valeur.text) ?? 0)})
          .eq('atelier_id', Session.instance.atelierId)
          .eq('user_id', l.userId);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _payer(_Ligne l, String libelleMois) async {
    final montant = TextEditingController(text: nombreChamp(l.reste > 0 ? l.reste : null));
    var mode = 'especes';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: Text('Payer ${l.nom}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Reste dû pour $libelleMois : ${argent(l.reste)}'),
            const SizedBox(height: 12),
            ChampNombre(controller: montant, label: 'Montant versé', suffixe: Session.instance.devise, obligatoire: true),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'Mode'),
              items: [for (final e in modesPaiement.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => mode = v ?? 'especes'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer le paiement')),
          ],
        ),
      ),
    );
    final m = lireNombre(montant.text) ?? 0;
    if (ok != true || m <= 0) return;
    try {
      await supa.from('depenses').insert({
        'atelier_id': Session.instance.atelierId,
        'categorie': 'salaire',
        'libelle': 'Paie ${l.nom} - $libelleMois',
        'montant': m,
        'mode': mode,
        'membre_id': l.userId,
        'periode': _periode,
      });
      if (mounted) snack(context, 'Paiement de ${argent(m)} enregistré (visible dans la caisse)');
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final libelleMois = DateFormat('MMMM yyyy', 'fr_FR').format(_mois);
    final moisCourant = _mois.year == DateTime.now().year && _mois.month == DateTime.now().month;
    return Scaffold(
      appBar: AppBar(title: const Text('Paie des couturiers')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            IconButton(onPressed: () => _changerMois(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(libelleMois[0].toUpperCase() + libelleMois.substring(1),
                  textAlign: TextAlign.center, style: t.textTheme.titleMedium),
            ),
            IconButton(onPressed: moisCourant ? null : () => _changerMois(1), icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        Expanded(
          child: AsyncVue<List<_Ligne>>(
            future: _f,
            onReessayer: _recharger,
            builder: (context, lignes) {
              if (lignes.isEmpty) {
                return const EtatVide(
                  icone: Icons.groups_outlined,
                  message: 'Aucun employé. Ajoutez votre équipe depuis Plus → Équipe.',
                );
              }
              final totalDu = lignes.fold<double>(0, (s, l) => s + l.du);
              final totalPaye = lignes.fold<double>(0, (s, l) => s + l.paye);
              return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('Une commande compte pour le couturier assigné le mois où elle passe à « Prête ». '
                      'Les versements sont enregistrés dans la caisse (dépenses « Salaires »).'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Total dû : ${argent(totalDu)} · déjà versé : ${argent(totalPaye)}',
                      style: t.textTheme.titleSmall),
                ),
                for (final l in lignes)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          CircleAvatar(child: Text(l.nom.isEmpty ? '?' : l.nom.characters.first.toUpperCase())),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.nom, style: t.textTheme.titleMedium),
                              Text('${roles[l.membre['role']] ?? ''} · ${switch (l.mode) {
                                'piece' => '${argent(l.valeur)} par vêtement',
                                'pourcentage' => '${nombre(l.valeur)} % de la façon',
                                _ => 'tarif non défini',
                              }}', style: t.textTheme.bodySmall),
                            ]),
                          ),
                          if (Session.instance.estGestionnaire)
                            IconButton(tooltip: 'Tarif', onPressed: () => _tarif(l), icon: const Icon(Icons.tune)),
                        ]),
                        const SizedBox(height: 8),
                        Text('${l.vetements} vêtement(s) terminé(s) · ${l.commandes.length} commande(s)'
                            '${l.commandes.isEmpty ? '' : ' : ${l.commandes.join(', ')}'}'),
                        if (l.mode == 'pourcentage') Text('Façon facturée : ${argent(l.facon)}', style: t.textTheme.bodySmall),
                        const Divider(),
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Dû : ${argent(l.du)} · versé : ${argent(l.paye)}'),
                              Text('Reste : ${argent(l.reste)}',
                                  style: t.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: l.reste > 0 ? Colors.deepOrange : Colors.green,
                                  )),
                            ]),
                          ),
                          if (Session.instance.estGestionnaire)
                            FilledButton.tonalIcon(
                              onPressed: () => _payer(l, libelleMois),
                              icon: const Icon(Icons.payments),
                              label: const Text('Payer'),
                            ),
                        ]),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
