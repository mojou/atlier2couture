import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'abonnement_screen.dart';
import 'assistant_screen.dart';
import 'calculateur_screen.dart';
import 'client_form_screen.dart';
import 'commande_detail_screen.dart';
import 'document_form_screen.dart';
import 'rdv_form_screen.dart';
import 'stock_screen.dart';

class _Donnees {
  _Donnees(this.commandes, this.rdvs, this.stockBas, this.encaisse, this.impayes, this.nbClients, this.nbCommandesMois);

  final List<Map<String, dynamic>> commandes;
  final List<Map<String, dynamic>> rdvs;
  final List<Map<String, dynamic>> stockBas;
  final double encaisse;
  final double impayes;

  /// Consommation des quotas de la formule Gratuite.
  final int nbClients;
  final int nbCommandesMois;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onOnglet});

  final void Function(int) onOnglet;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_Donnees> _f = _charger();

  Future<_Donnees> _charger() async {
    final id = Session.instance.atelierId;
    final debutJour = aujourdhui();
    final finJour = debutJour.add(const Duration(days: 1));
    final n = DateTime.now();
    final debutMois = DateTime(n.year, n.month);
    final r = await Future.wait<List<Map<String, dynamic>>>([
      supa
          .from('commandes')
          .select('id, numero, statut, date_livraison, priorite, clients(nom)')
          .eq('atelier_id', id)
          .inFilter('statut', statutsEnCours)
          .order('date_livraison', ascending: true, nullsFirst: false),
      supa
          .from('rendez_vous')
          .select('*, clients(nom), commandes(numero)')
          .eq('atelier_id', id)
          .gte('debut', debutJour.toUtc().toIso8601String())
          .lt('debut', finJour.toUtc().toIso8601String())
          .neq('statut', 'annule')
          .order('debut'),
      supa
          .from('stock_articles')
          .select('id, nom, quantite, seuil_alerte, unite')
          .eq('atelier_id', id)
          .gt('seuil_alerte', 0),
      supa.from('paiements').select('montant').eq('atelier_id', id).gte('paye_le', debutMois.toUtc().toIso8601String()),
      supa
          .from('documents')
          .select('total, montant_paye')
          .eq('atelier_id', id)
          .eq('type', 'facture')
          .inFilter('statut', ['impayee', 'partielle']),
      supa.from('clients').select('id').eq('atelier_id', id).limit(1000),
      supa.from('commandes').select('id').eq('atelier_id', id).gte('created_at', debutMois.toUtc().toIso8601String()),
    ]);
    return _Donnees(
      r[0],
      r[1],
      r[2].where((a) => num0(a['quantite']) <= num0(a['seuil_alerte'])).toList(),
      r[3].fold<double>(0, (s, p) => s + num0(p['montant'])),
      r[4].fold<double>(0, (s, d) => s + num0(d['total']) - num0(d['montant_paye'])),
      r[5].length,
      r[6].length,
    );
  }

  Future<void> _recharger() async {
    setState(() => _f = _charger());
    await _f;
  }

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    if (mounted) _recharger();
  }

  String _resteEssai(DateTime fin) {
    final d = fin.difference(DateTime.now());
    if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min';
    return '${d.inMinutes < 1 ? 1 : d.inMinutes} min';
  }

  bool _enRetard(Map<String, dynamic> c) {
    final d = lireDate(c['date_livraison']);
    return d != null && c['statut'] != 'prete' && d.isBefore(aujourdhui());
  }

  @override
  Widget build(BuildContext context) {
    final atelier = Session.instance.atelier;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          if (atelier['logo_url'] != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(atelier['logo_url'] as String, width: 32, height: 32, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          Expanded(child: Text(atelier['nom'] as String? ?? '', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Assistant',
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: () => _ouvrir(const AssistantScreen()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _recharger,
        child: AsyncVue<_Donnees>(
          future: _f,
          onReessayer: _recharger,
          builder: (context, d) {
            final retards = d.commandes.where(_enRetard).toList();
            final t = Theme.of(context);
            final essai = Session.instance.enEssai ? Session.instance.essaiFin : null;
            final offre = Session.instance.offre;
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              if (offre.maxClients != null)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  color: Colors.amber.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                    title: Text('Formule ${offre.nom} : ${d.nbClients}/${offre.maxClients} clients · '
                        '${d.nbCommandesMois}/${offre.maxCommandesMois} commandes ce mois'),
                    subtitle: const Text('Passez à Standard (5 000 / mois) pour tout débloquer.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _ouvrir(const AbonnementScreen()),
                  ),
                ),
              if (essai != null)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  color: Colors.blue.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.timer_outlined, color: Colors.blue),
                    title: Text('Période d\'essai : encore ${_resteEssai(essai)}'),
                    subtitle: Text('Se termine le ${dateHeure(essai)}. Contactez l\'administrateur '
                        'de la plateforme pour activer définitivement votre atelier.'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  _Kpi('En cours', '${d.commandes.length}', Icons.receipt_long, Colors.indigo,
                      () => widget.onOnglet(1)),
                  _Kpi('En retard', '${retards.length}', Icons.warning_amber,
                      retards.isEmpty ? Colors.green : Colors.red, () => widget.onOnglet(1)),
                  _Kpi('RDV du jour', '${d.rdvs.length}', Icons.event, Colors.purple, () => widget.onOnglet(3)),
                  _Kpi('Encaissé ce mois', argent(d.encaisse), Icons.payments, Colors.teal, null),
                  _Kpi('Impayés', argent(d.impayes), Icons.money_off, Colors.orange, null),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () => _ouvrir(const DocumentFormScreen(mode: 'commande')),
                    icon: const Icon(Icons.add),
                    label: const Text('Nouvelle commande'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _ouvrir(const CalculateurScreen()),
                    icon: const Icon(Icons.straighten),
                    label: const Text('Calculer un métrage'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _ouvrir(const ClientFormScreen()),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Client'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _ouvrir(const RdvFormScreen()),
                    icon: const Icon(Icons.event_available),
                    label: const Text('Rendez-vous'),
                  ),
                ]),
              ),
              Section(
                titre: 'À livrer bientôt',
                children: [
                  if (d.commandes.isEmpty) const Text('Aucune commande en cours.'),
                  for (final c in d.commandes.take(6))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(c['priorite'] == 'urgente' ? Icons.bolt : Icons.checkroom,
                          color: c['priorite'] == 'urgente' ? Colors.red : null),
                      title: Text('${(c['clients'] as Map?)?['nom'] ?? ''} · ${c['numero'] ?? ''}'),
                      subtitle: Text('Livraison : ${dateCourte(lireDate(c['date_livraison']))}',
                          style: TextStyle(color: _enRetard(c) ? Colors.red : null)),
                      trailing: Pastille(libellesStatut[c['statut']] ?? '', couleurStatut(c['statut'] as String)),
                      onTap: () => _ouvrir(CommandeDetailScreen(commandeId: c['id'] as String)),
                    ),
                ],
              ),
              Section(
                titre: 'Rendez-vous du jour',
                children: [
                  if (d.rdvs.isEmpty) const Text('Aucun rendez-vous aujourd\'hui.'),
                  for (final r in d.rdvs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(iconeRdv(r['type'] as String)),
                      title: Text('${heure(lireDate(r['debut'])!)} · ${(r['clients'] as Map?)?['nom'] ?? ''}'),
                      subtitle: Text(typesRdv[r['type']] ?? ''),
                      onTap: () => _ouvrir(RdvFormScreen(rdv: r)),
                    ),
                ],
              ),
              if (d.stockBas.isNotEmpty)
                Section(
                  titre: 'Stock bas',
                  action: TextButton(
                      onPressed: () => _ouvrir(const StockScreen()), child: const Text('Voir le stock')),
                  children: [
                    for (final a in d.stockBas)
                      Row(children: [
                        const Icon(Icons.inventory_2, size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a['nom'] as String)),
                        Text('${nombre(num0(a['quantite']))} ${a['unite']}',
                            style: t.textTheme.bodyMedium?.copyWith(color: Colors.red)),
                      ]),
                  ],
                ),
            ]);
          },
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.titre, this.valeur, this.icone, this.couleur, this.onTap);

  final String titre;
  final String valeur;
  final IconData icone;
  final Color couleur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icone, color: couleur),
              const SizedBox(height: 6),
              FittedBox(
                child: Text(valeur, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Text(titre, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }
}
