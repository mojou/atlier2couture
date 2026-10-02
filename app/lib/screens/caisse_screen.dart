import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

class _Bilan {
  _Bilan(this.encaisse, this.depenses, this.nbPaiements);

  final double encaisse;
  final List<Map<String, dynamic>> depenses;
  final int nbPaiements;

  double get totalDepenses => depenses.fold<double>(0, (s, d) => s + num0(d['montant']));
  double get benefice => encaisse - totalDepenses;

  Map<String, double> get parCategorie {
    final m = <String, double>{};
    for (final d in depenses) {
      final c = d['categorie'] as String;
      m[c] = (m[c] ?? 0) + num0(d['montant']);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
}

/// Caisse de l'atelier : encaissements, dépenses et bénéfice du mois.
class CaisseScreen extends StatefulWidget {
  const CaisseScreen({super.key});

  @override
  State<CaisseScreen> createState() => _CaisseScreenState();
}

class _CaisseScreenState extends State<CaisseScreen> {
  DateTime _mois = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<_Bilan> _f = _charger();

  Future<_Bilan> _charger() async {
    final a = Session.instance.atelierId;
    final debut = _mois;
    final fin = DateTime(_mois.year, _mois.month + 1);
    final r = await Future.wait<List<Map<String, dynamic>>>([
      supa
          .from('paiements')
          .select('montant')
          .eq('atelier_id', a)
          .gte('paye_le', debut.toUtc().toIso8601String())
          .lt('paye_le', fin.toUtc().toIso8601String()),
      supa
          .from('depenses')
          .select()
          .eq('atelier_id', a)
          .gte('date', isoDate(debut))
          .lt('date', isoDate(fin))
          .order('date', ascending: false)
          .order('created_at', ascending: false),
    ]);
    return _Bilan(r[0].fold<double>(0, (s, p) => s + num0(p['montant'])), r[1], r[0].length);
  }

  void _changerMois(int delta) => setState(() {
        _mois = DateTime(_mois.year, _mois.month + delta);
        _f = _charger();
      });

  Future<void> _ajouter() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _DialogueDepense());
    if (ok == true) setState(() => _f = _charger());
  }

  Future<void> _supprimer(Map<String, dynamic> d) async {
    if (!await confirmer(context, 'Supprimer la dépense', 'Supprimer « ${d['libelle']} » (${argent(num0(d['montant']))}) ?',
        ok: 'Supprimer')) {
      return;
    }
    try {
      await supa.from('depenses').delete().eq('id', d['id'] as String);
      setState(() => _f = _charger());
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final titreMois = DateFormat('MMMM yyyy', 'fr_FR').format(_mois);
    final moisCourant = _mois.year == DateTime.now().year && _mois.month == DateTime.now().month;
    return Scaffold(
      appBar: AppBar(title: const Text('Caisse et dépenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ajouter,
        icon: const Icon(Icons.add),
        label: const Text('Dépense'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            IconButton(onPressed: () => _changerMois(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(titreMois[0].toUpperCase() + titreMois.substring(1),
                  textAlign: TextAlign.center, style: t.textTheme.titleMedium),
            ),
            IconButton(onPressed: moisCourant ? null : () => _changerMois(1), icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        Expanded(
          child: AsyncVue<_Bilan>(
            future: _f,
            onReessayer: () => setState(() => _f = _charger()),
            builder: (context, b) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Expanded(child: _Chiffre('Encaissé', argent(b.encaisse), Colors.teal, '${b.nbPaiements} paiement(s)')),
                  const SizedBox(width: 8),
                  Expanded(child: _Chiffre('Dépensé', argent(b.totalDepenses), Colors.deepOrange, '${b.depenses.length} dépense(s)')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _Chiffre(
                  b.benefice >= 0 ? 'Bénéfice du mois' : 'Perte du mois',
                  argent(b.benefice),
                  b.benefice >= 0 ? Colors.green : Colors.red,
                  'Encaissements moins dépenses',
                  grand: true,
                ),
              ),
              if (b.parCategorie.isNotEmpty)
                Section(titre: 'Dépenses par catégorie', children: [
                  for (final e in b.parCategorie.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Icon(iconeDepense(e.key), size: 20, color: t.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text(categoriesDepense[e.key] ?? e.key)),
                        Text(argent(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                ]),
              Section(titre: 'Détail des dépenses', children: [
                if (b.depenses.isEmpty) const Text('Aucune dépense ce mois-ci.'),
                for (final d in b.depenses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Icon(iconeDepense(d['categorie'] as String), size: 20)),
                    title: Text(d['libelle'] as String),
                    subtitle: Text('${dateCourte(lireDate(d['date']))} · ${categoriesDepense[d['categorie']] ?? ''}'
                        ' · ${modesPaiement[d['mode']] ?? ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(argent(num0(d['montant'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (Session.instance.estGestionnaire || d['created_by'] == utilisateurId)
                        IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _supprimer(d)),
                    ]),
                  ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre(this.titre, this.valeur, this.couleur, this.detail, {this.grand = false});

  final String titre;
  final String valeur;
  final Color couleur;
  final String detail;
  final bool grand;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: couleur.withAlpha(22),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: t.textTheme.bodySmall),
          FittedBox(
            child: Text(valeur,
                style: (grand ? t.textTheme.headlineSmall : t.textTheme.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.bold, color: couleur)),
          ),
          Text(detail, style: t.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _DialogueDepense extends StatefulWidget {
  const _DialogueDepense();

  @override
  State<_DialogueDepense> createState() => _DialogueDepenseState();
}

class _DialogueDepenseState extends State<_DialogueDepense> {
  final _form = GlobalKey<FormState>();
  final _libelle = TextEditingController();
  final _montant = TextEditingController();
  String _categorie = 'tissu';
  String _mode = 'especes';
  DateTime _date = aujourdhui();
  bool _occupe = false;

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _occupe = true);
    try {
      await supa.from('depenses').insert({
        'atelier_id': Session.instance.atelierId,
        'date': isoDate(_date),
        'categorie': _categorie,
        'libelle': _libelle.text.trim(),
        'montant': lireNombre(_montant.text),
        'mode': _mode,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle dépense'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: _categorie,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: [
                for (final e in categoriesDepense.entries)
                  if (e.key != 'salaire') DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _categorie = v ?? 'autre'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _libelle,
              decoration: const InputDecoration(labelText: 'Libellé *', hintText: 'ex. 12 yards de wax au marché'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
            ),
            const SizedBox(height: 12),
            ChampNombre(controller: _montant, label: 'Montant', suffixe: Session.instance.devise, obligatoire: true),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Payé par'),
              items: [for (final e in modesPaiement.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _mode = v ?? 'especes'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Le ${dateCourte(_date)}'),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: aujourdhui(),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: _occupe ? null : _enregistrer, child: const Text('Enregistrer')),
      ],
    );
  }
}
