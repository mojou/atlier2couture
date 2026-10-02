import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/support.dart';
import '../core/widgets.dart';

const _statutsPaiement = {
  'en_attente': ('En attente', Colors.orange),
  'paye': ('Payé', Colors.green),
  'echoue': ('Échoué', Colors.red),
  'annule': ('Annulé', Colors.grey),
};

/// Formules d'abonnement et paiement par SasPay (Mobile Money).
class AbonnementScreen extends StatefulWidget {
  const AbonnementScreen({super.key});

  @override
  State<AbonnementScreen> createState() => _AbonnementScreenState();
}

class _AbonnementScreenState extends State<AbonnementScreen> with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> _historique = _chargerHistorique();
  late String _pays = _paysParDefaut();
  int _mois = 1;
  bool _occupe = false;
  bool _paiementLance = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Un paiement a pu aboutir pendant que l'application était fermée.
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifier(silencieux: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retour dans l'application après la page de paiement : on vérifie.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _paiementLance) _verifier(silencieux: true);
  }

  String _paysParDefaut() {
    final p = (Session.instance.atelier['pays'] as String? ?? '').toLowerCase();
    for (final e in paysPaiement.entries) {
      final nom = e.value.$1.toLowerCase();
      if (p.isNotEmpty && (nom.contains(p) || p.contains(nom.split(' ').first))) return e.key;
    }
    return 'CM';
  }

  Future<List<Map<String, dynamic>>> _chargerHistorique() => supa
      .from('abonnement_paiements')
      .select()
      .eq('atelier_id', Session.instance.atelierId)
      .order('created_at', ascending: false)
      .limit(30);

  Future<void> _rechargerAtelier() async {
    final a = await supa.from('ateliers').select().eq('id', Session.instance.atelierId).single();
    Session.instance.majAtelier(a);
  }

  Future<void> _payer(Formule f) async {
    final (nomPays, devise) = paysPaiement[_pays]!;
    final total = f.prixMois * _mois;
    final actuelle = Session.instance.formule;
    final changement = actuelle != 'gratuit' && actuelle != f.code;
    final ok = await confirmer(
      context,
      'Formule ${f.nom}',
      'Montant : $total $devise pour $_mois mois ($nomPays).\n\n'
          'Vous allez être redirigé vers la page de paiement sécurisée SasPay '
          '(Orange Money, MTN MoMo, Wave… selon le pays).'
          '${changement ? '\n\nAttention : votre formule actuelle (${formules[actuelle]!.nom}) sera remplacée '
              'dès le paiement, sans report des jours restants.' : ''}',
      ok: 'Payer $total $devise',
    );
    if (!ok) return;
    setState(() => _occupe = true);
    try {
      final r = await supa.functions.invoke('saspay-checkout', body: {
        'atelier_id': Session.instance.atelierId,
        'formule': f.code,
        'mois': _mois,
        'pays': _pays,
      });
      final url = (r.data as Map?)?['checkout_url'] as String?;
      if (url == null) throw Exception('Lien de paiement introuvable');
      _paiementLance = true;
      final ouvert = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ouvert && mounted) snack(context, 'Impossible d\'ouvrir la page de paiement', erreur: true);
      setState(() => _historique = _chargerHistorique());
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _verifier({bool silencieux = false}) async {
    if (!Session.instance.estGestionnaire) return;
    if (!silencieux) setState(() => _occupe = true);
    try {
      final r = await supa.functions.invoke('saspay-verifier', body: {'atelier_id': Session.instance.atelierId});
      final payes = ((r.data as Map?)?['payes'] as num?)?.toInt() ?? 0;
      if (payes > 0) {
        await _rechargerAtelier();
        _paiementLance = false;
        if (mounted) snack(context, 'Paiement confirmé : formule ${Session.instance.offre.nom} activée. Merci !');
      } else if (!silencieux && mounted) {
        snack(context, 'Paiement non finalisé : aucun montant n\'a été débité. '
            'Si vous venez de valider sur votre téléphone, patientez quelques secondes puis vérifiez à nouveau.');
      }
      if (mounted) setState(() => _historique = _chargerHistorique());
    } catch (e) {
      if (!silencieux && mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (!silencieux && mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) {
        final s = Session.instance;
        final t = Theme.of(context);
        final fin = s.formuleFin;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mon abonnement'),
            actions: [
              if (s.estGestionnaire)
                IconButton(
                  tooltip: 'Vérifier mes paiements',
                  onPressed: _occupe ? null : () => _verifier(),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Card(
              margin: const EdgeInsets.all(12),
              color: t.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Formule actuelle', style: t.textTheme.bodySmall),
                  Text(s.offre.nom, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  if (s.formule != 'gratuit' && fin != null)
                    Text('Valable jusqu\'au ${dateCourte(fin)} (${fin.difference(DateTime.now()).inDays} jours restants)'),
                  if (s.formule == 'gratuit')
                    const Text('Passez à une formule payante pour lever les limites.'),
                ]),
              ),
            ),
            if (_paiementLance)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.orange.shade50,
                child: ListTile(
                  leading: const Icon(Icons.hourglass_top, color: Colors.orange),
                  title: const Text('Paiement en cours'),
                  subtitle: const Text('Une fois le paiement validé sur la page SasPay, revenez ici : '
                      'la formule s\'active automatiquement. Vous n\'avez pas payé ? Fermez ce message.'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: _occupe ? null : () => _verifier(), child: const Text('Vérifier')),
                    IconButton(
                      tooltip: 'Fermer',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _paiementLance = false),
                    ),
                  ]),
                ),
              ),
            if (!s.estGestionnaire)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Seuls le propriétaire et le gérant de l\'atelier peuvent changer de formule.'),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DropdownButtonFormField<String>(
                    initialValue: _pays,
                    decoration: const InputDecoration(labelText: 'Pays du paiement (Mobile Money)'),
                    items: [
                      for (final e in paysPaiement.entries)
                        DropdownMenuItem(value: e.key, child: Text('${e.value.$1} (${e.value.$2})')),
                    ],
                    onChanged: (v) => setState(() => _pays = v ?? 'CM'),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: [
                      for (final m in dureesAbonnement) ButtonSegment(value: m, label: Text('$m mois')),
                    ],
                    selected: {_mois},
                    onSelectionChanged: (v) => setState(() => _mois = v.first),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            for (final f in formules.values) _carteFormule(f),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: BlocSupport(
                titre: 'Une question sur les formules ou un paiement ?',
                sujet: 'J\'ai une question sur mon abonnement.',
              ),
            ),
            Section(
              titre: 'Historique des paiements',
              children: [
                AsyncVue<List<Map<String, dynamic>>>(
                  future: _historique,
                  builder: (context, paiements) {
                    if (paiements.isEmpty) return const Text('Aucun paiement.');
                    return Column(children: [
                      for (final p in paiements)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${formules[p['formule']]?.nom ?? p['formule']} · ${p['mois']} mois'),
                          subtitle: Text('${dateHeure(lireDate(p['created_at'])!)} · '
                              '${nombre(num0(p['montant']))} ${p['devise']}'),
                          trailing: Pastille(
                            _statutsPaiement[p['statut']]?.$1 ?? p['statut'] as String,
                            _statutsPaiement[p['statut']]?.$2 ?? Colors.grey,
                          ),
                        ),
                    ]);
                  },
                ),
              ],
            ),
          ]),
        );
      },
    );
  }

  Widget _carteFormule(Formule f) {
    final s = Session.instance;
    final t = Theme.of(context);
    final actuelle = s.formule == f.code;
    final devise = paysPaiement[_pays]!.$2;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: actuelle ? t.colorScheme.primary : Colors.transparent, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(f.nom, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
            Text(f.prixMois == 0 ? 'Gratuit' : '${nombre(f.prixMois)} $devise / mois',
                style: t.textTheme.titleMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          for (final a in f.avantages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Icon(Icons.check_circle, size: 18, color: t.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(a)),
              ]),
            ),
          const SizedBox(height: 12),
          if (actuelle)
            OutlinedButton.icon(
              onPressed: f.prixMois > 0 && s.estGestionnaire && !_occupe ? () => _payer(f) : null,
              icon: const Icon(Icons.check),
              label: Text(f.prixMois > 0 ? 'Formule actuelle · prolonger de $_mois mois' : 'Formule actuelle'),
            )
          else if (f.prixMois > 0)
            FilledButton.icon(
              onPressed: s.estGestionnaire && !_occupe ? () => _payer(f) : null,
              icon: const Icon(Icons.lock_open),
              label: Text('Choisir ${f.nom} · ${nombre(f.prixMois * _mois)} $devise'),
            ),
        ]),
      ),
    );
  }
}

/// Explique une fonction réservée à une formule supérieure et propose de changer.
Future<void> proposerFormule(BuildContext context, String message) async {
  final voir = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.workspace_premium, size: 40, color: Colors.amber),
      title: const Text('Fonction non incluse'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Plus tard')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Voir les formules')),
      ],
    ),
  );
  if (voir == true && context.mounted) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AbonnementScreen()));
  }
}
