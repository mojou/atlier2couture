import 'package:flutter/material.dart';

import '../calcul/devis.dart';
import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'commande_detail_screen.dart';
import 'document_form_screen.dart';
import 'facture_pdf_screen.dart';
import 'paiement_dialog.dart';

class _Vue {
  _Vue(this.doc, this.paiements);

  final Map<String, dynamic> doc;
  final List<Map<String, dynamic>> paiements;
}

class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  late Future<_Vue> _f = _charger();

  Future<_Vue> _charger() async {
    final d = await supa.from('documents').select('*, clients(*)').eq('id', widget.documentId).single();
    final p = await supa.from('paiements').select().eq('document_id', widget.documentId).order('paye_le');
    return _Vue(d, p);
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _ouvrir(Widget ecran, {bool remplacer = false}) async {
    final route = MaterialPageRoute<void>(builder: (_) => ecran);
    if (remplacer) {
      await Navigator.of(context).pushReplacement(route);
      return;
    }
    await Navigator.of(context).push(route);
    if (mounted) _recharger();
  }

  Future<void> _statut(String s) async {
    try {
      await supa.from('documents').update({'statut': s}).eq('id', widget.documentId);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _supprimerPaiement(Map<String, dynamic> p) async {
    final ok = await confirmer(context, 'Supprimer le paiement', 'Supprimer ce paiement de ${argent(num0(p['montant']))} ?',
        ok: 'Supprimer');
    if (!ok) return;
    try {
      await supa.from('paiements').delete().eq('id', p['id'] as String);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  void _pdf(_Vue v) {
    final d = v.doc;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FacturePdfScreen(
        doc: d,
        client: d['clients'] as Map<String, dynamic>,
        paiements: v.paiements,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AsyncVue<_Vue>(
      future: _f,
      onReessayer: _recharger,
      pleinEcran: true,
      builder: (context, v) {
        final d = v.doc;
        final facture = d['type'] == 'facture';
        final statut = d['statut'] as String;
        final lignes = [
          for (final l in (d['lignes'] as List? ?? const [])) LigneDoc.depuisJson(Map<String, dynamic>.from(l as Map))
        ];
        final total = num0(d['total']);
        final paye = num0(d['montant_paye']);
        final t = Theme.of(context);
        final modifiable = !facture && ['brouillon', 'envoye'].contains(statut);

        return Scaffold(
          appBar: AppBar(
            title: Text(d['numero'] as String? ?? ''),
            actions: [
              IconButton(tooltip: 'PDF / partager', icon: const Icon(Icons.picture_as_pdf), onPressed: () => _pdf(v)),
              if (!facture || Session.instance.estGestionnaire)
                PopupMenuButton<String>(
                  onSelected: (a) async {
                    switch (a) {
                      case 'modifier':
                        _ouvrir(DocumentFormScreen(mode: 'devis', devis: d), remplacer: true);
                      case 'annuler':
                        if (await confirmer(context, 'Annuler la facture', 'La facture restera visible mais marquée annulée.',
                            ok: 'Annuler la facture')) {
                          _statut('annulee');
                        }
                      default:
                        _statut(a);
                    }
                  },
                  itemBuilder: (_) => [
                    if (modifiable) const PopupMenuItem(value: 'modifier', child: Text('Modifier le devis')),
                    if (!facture && statut != 'envoye') const PopupMenuItem(value: 'envoye', child: Text('Marquer envoyé')),
                    if (!facture && statut != 'refuse') const PopupMenuItem(value: 'refuse', child: Text('Marquer refusé')),
                    if (facture && statut != 'annulee' && Session.instance.estGestionnaire)
                      const PopupMenuItem(value: 'annuler', child: Text('Annuler la facture')),
                  ],
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Section(titre: facture ? 'Facture' : 'Devis', children: [
              Row(children: [
                Expanded(child: Text((d['clients'] as Map?)?['nom'] as String? ?? '', style: t.textTheme.titleMedium)),
                Pastille(statutsDocument[statut] ?? statut, couleurStatutDocument(statut)),
              ]),
              Text('Émis le ${dateCourte(lireDate(d['date_emission']))}'
                  '${d['date_echeance'] == null ? '' : ' · ${facture ? 'échéance' : 'valable jusqu\'au'} ${dateCourte(lireDate(d['date_echeance']))}'}'),
            ]),
            Section(titre: 'Détail', children: [
              for (final l in lignes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.designation),
                        Text('${nombre(l.quantite)} ${l.unite} × ${argent(l.prixUnitaire)}', style: t.textTheme.bodySmall),
                      ]),
                    ),
                    Text(argent(l.montant)),
                  ]),
                ),
              const Divider(),
              _ligne('Sous-total', argent(num0(d['sous_total']))),
              if (num0(d['remise_montant']) > 0) _ligne('Remise', '- ${argent(num0(d['remise_montant']))}'),
              if (num0(d['montant_tva']) > 0) _ligne('TVA (${nombre(num0(d['taux_tva']))} %)', argent(num0(d['montant_tva']))),
              _ligne('Total', argent(total), gras: true),
              if (facture) ...[
                _ligne('Payé', argent(paye)),
                _ligne('Reste à payer', argent(total - paye), gras: true),
              ],
            ]),
            if (facture)
              Section(
                titre: 'Paiements',
                action: statut != 'payee' && statut != 'annulee'
                    ? FilledButton.tonalIcon(
                        onPressed: () async {
                          if (await encaisser(context, d)) _recharger();
                        },
                        icon: const Icon(Icons.payments),
                        label: const Text('Encaisser'),
                      )
                    : null,
                children: [
                  if (v.paiements.isEmpty) const Text('Aucun paiement.'),
                  for (final p in v.paiements)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(argent(num0(p['montant']))),
                      subtitle: Text('${dateHeure(lireDate(p['paye_le'])!)} · ${modesPaiement[p['mode']] ?? p['mode']}'
                          '${p['reference'] == null ? '' : ' · ${p['reference']}'}'),
                      trailing: Session.instance.estGestionnaire
                          ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _supprimerPaiement(p))
                          : null,
                    ),
                ],
              ),
            if (d['notes'] != null) Section(titre: 'Notes', children: [Text(d['notes'] as String)]),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton.icon(
                  onPressed: () => _pdf(v),
                  icon: const Icon(Icons.share),
                  label: const Text('PDF : imprimer ou envoyer (WhatsApp…)'),
                ),
                const SizedBox(height: 8),
                if (!facture && d['commande_id'] == null && statut != 'refuse')
                  FilledButton.tonalIcon(
                    onPressed: () => _ouvrir(DocumentFormScreen(mode: 'commande', devis: d), remplacer: true),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Le client accepte : créer la commande'),
                  ),
                if (d['commande_id'] != null)
                  OutlinedButton.icon(
                    onPressed: () => _ouvrir(CommandeDetailScreen(commandeId: d['commande_id'] as String)),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Voir la commande'),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _ligne(String libelle, String valeur, {bool gras = false}) {
    final style = gras ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(libelle, style: style)), Text(valeur, style: style)]),
    );
  }
}
