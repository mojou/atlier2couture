import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

class _Stats {
  _Stats(this.mois, this.encaisse, this.nbCommandes, this.montantCommandes, this.topClients, this.topModeles,
      this.impayes, this.delaiMoyen);

  /// 6 derniers mois, du plus ancien au plus récent.
  final List<DateTime> mois;
  final Map<DateTime, double> encaisse;
  final Map<DateTime, int> nbCommandes;
  final Map<DateTime, double> montantCommandes;
  final List<(String, double, int)> topClients;
  final List<(String, int)> topModeles;
  final double impayes;

  /// Délai moyen entre la commande et la livraison prévue (jours).
  final double? delaiMoyen;
}

/// Statistiques avancées de l'atelier (formule Premium).
class StatistiquesScreen extends StatefulWidget {
  const StatistiquesScreen({super.key});

  @override
  State<StatistiquesScreen> createState() => _StatistiquesScreenState();
}

class _StatistiquesScreenState extends State<StatistiquesScreen> {
  late Future<_Stats> _f = _charger();

  Future<_Stats> _charger() async {
    final id = Session.instance.atelierId;
    final n = DateTime.now();
    final mois = [for (var i = 5; i >= 0; i--) DateTime(n.year, n.month - i)];
    final debut = mois.first.toUtc().toIso8601String();
    final r = await Future.wait<List<Map<String, dynamic>>>([
      supa.from('paiements').select('montant, paye_le').eq('atelier_id', id).gte('paye_le', debut),
      supa
          .from('commandes')
          .select('total, statut, articles, date_commande, date_livraison, created_at, clients(nom)')
          .eq('atelier_id', id)
          .gte('created_at', debut)
          .neq('statut', 'annulee'),
      supa
          .from('documents')
          .select('total, montant_paye')
          .eq('atelier_id', id)
          .eq('type', 'facture')
          .inFilter('statut', ['impayee', 'partielle']),
    ]);

    DateTime cle(String iso) {
      final d = DateTime.parse(iso).toLocal();
      return DateTime(d.year, d.month);
    }

    final encaisse = {for (final m in mois) m: 0.0};
    for (final p in r[0]) {
      final k = cle(p['paye_le'] as String);
      encaisse[k] = (encaisse[k] ?? 0) + num0(p['montant']);
    }

    final nb = {for (final m in mois) m: 0};
    final montants = {for (final m in mois) m: 0.0};
    final clients = <String, (double, int)>{};
    final modeles = <String, int>{};
    var delais = 0;
    var nbDelais = 0;
    for (final c in r[1]) {
      final k = cle(c['created_at'] as String);
      nb[k] = (nb[k] ?? 0) + 1;
      montants[k] = (montants[k] ?? 0) + num0(c['total']);
      final nom = (c['clients'] as Map?)?['nom'] as String? ?? '?';
      final (total, compte) = clients[nom] ?? (0.0, 0);
      clients[nom] = (total + num0(c['total']), compte + 1);
      for (final a in (c['articles'] as List? ?? const [])) {
        final d = ((a as Map)['designation'] as String? ?? '').trim();
        if (d.isNotEmpty) modeles[d] = (modeles[d] ?? 0) + ((a['quantite'] as num?)?.toInt() ?? 1);
      }
      final dc = lireDate(c['date_commande']);
      final dl = lireDate(c['date_livraison']);
      if (dc != null && dl != null) {
        delais += dl.difference(dc).inDays;
        nbDelais++;
      }
    }

    final topClients = clients.entries.map((e) => (e.key, e.value.$1, e.value.$2)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final topModeles = modeles.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));

    return _Stats(
      mois,
      encaisse,
      nb,
      montants,
      topClients.take(5).toList(),
      topModeles.take(5).toList(),
      r[2].fold<double>(0, (s, d) => s + num0(d['total']) - num0(d['montant_paye'])),
      nbDelais == 0 ? null : delais / nbDelais,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques avancées')),
      body: AsyncVue<_Stats>(
        future: _f,
        onReessayer: () => setState(() => _f = _charger()),
        builder: (context, s) {
          final nomMois = DateFormat('MMM yy', 'fr_FR');
          final totalEncaisse = s.encaisse.values.fold<double>(0, (a, b) => a + b);
          final totalCommandes = s.nbCommandes.values.fold<int>(0, (a, b) => a + b);
          final totalMontant = s.montantCommandes.values.fold<double>(0, (a, b) => a + b);
          return RefreshIndicator(
            onRefresh: () async => setState(() => _f = _charger()),
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  _Tuile('Encaissé (6 mois)', argent(totalEncaisse)),
                  _Tuile('Commandes (6 mois)', '$totalCommandes'),
                  _Tuile('Panier moyen', argent(totalCommandes == 0 ? 0 : totalMontant / totalCommandes)),
                  _Tuile('Impayés', argent(s.impayes)),
                  if (s.delaiMoyen != null) _Tuile('Délai moyen', '${nombre(s.delaiMoyen, max: 1)} jours'),
                ]),
              ),
              Section(titre: 'Encaissements par mois', children: [
                _Barres(
                  valeurs: [for (final m in s.mois) (nomMois.format(m), s.encaisse[m] ?? 0)],
                  format: argent,
                  couleur: Colors.teal,
                ),
              ]),
              Section(titre: 'Commandes par mois', children: [
                _Barres(
                  valeurs: [for (final m in s.mois) (nomMois.format(m), (s.nbCommandes[m] ?? 0).toDouble())],
                  format: (v) => '${v.toInt()}',
                  couleur: Colors.indigo,
                ),
              ]),
              Section(titre: 'Meilleurs clients (6 mois)', children: [
                if (s.topClients.isEmpty) const Text('Pas encore de commandes.'),
                for (final (i, c) in s.topClients.indexed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                    title: Text(c.$1),
                    subtitle: Text('${c.$3} commande(s)'),
                    trailing: Text(argent(c.$2), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ]),
              Section(titre: 'Modèles les plus commandés', children: [
                if (s.topModeles.isEmpty) const Text('Pas encore de commandes.'),
                for (final m in s.topModeles)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.checkroom),
                    title: Text(m.$1),
                    trailing: Text('×${m.$2}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ]),
            ]),
          );
        },
      ),
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile(this.titre, this.valeur);

  final String titre;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              child: Text(valeur,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(titre, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// Barres horizontales simples (libellé, barre proportionnelle, valeur).
class _Barres extends StatelessWidget {
  const _Barres({required this.valeurs, required this.format, required this.couleur});

  final List<(String, double)> valeurs;
  final String Function(double) format;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final max = valeurs.fold<double>(0, (m, v) => v.$2 > m ? v.$2 : m);
    return Column(children: [
      for (final (libelle, v) in valeurs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 56, child: Text(libelle, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 18,
                    width: max == 0 ? 2 : (c.maxWidth * v / max).clamp(2, c.maxWidth),
                    decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 96, child: Text(format(v), textAlign: TextAlign.right)),
          ]),
        ),
    ]);
  }
}
