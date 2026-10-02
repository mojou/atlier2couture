import 'package:flutter/material.dart';

import '../calcul/calcul.dart';
import '../calcul/devis.dart';
import '../core/constantes.dart';
import '../core/contact.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../models/article_commande.dart';
import '../pdf/documents_pdf.dart';
import 'client_detail_screen.dart';
import 'document_detail_screen.dart';
import 'messagerie_screen.dart';
import 'paiement_dialog.dart';
import 'pdf_screen.dart';
import 'rdv_form_screen.dart';

class _Vue {
  _Vue(this.commande, this.facture, this.historique, this.membres, this.rdvs);

  final Map<String, dynamic> commande;
  final Map<String, dynamic>? facture;
  final List<Map<String, dynamic>> historique;
  final List<Map<String, dynamic>> membres;
  final List<Map<String, dynamic>> rdvs;
}

/// Suivi d'une commande : étapes de production, couturier assigné, coupe,
/// facture et paiements, rendez-vous.
class CommandeDetailScreen extends StatefulWidget {
  const CommandeDetailScreen({super.key, required this.commandeId});

  final String commandeId;

  @override
  State<CommandeDetailScreen> createState() => _CommandeDetailScreenState();
}

class _CommandeDetailScreenState extends State<CommandeDetailScreen> {
  late Future<_Vue> _f = _charger();

  Future<_Vue> _charger() async {
    final id = widget.commandeId;
    final c = await supa.from('commandes').select('*, clients(*)').eq('id', id).single();
    final r = await Future.wait<List<Map<String, dynamic>>>([
      supa.from('documents').select().eq('commande_id', id).eq('type', 'facture').neq('statut', 'annulee'),
      supa.from('commande_historique').select().eq('commande_id', id).order('created_at'),
      supa.from('membres').select('user_id, nom, role').eq('atelier_id', Session.instance.atelierId),
      supa.from('rendez_vous').select('*, clients(nom)').eq('commande_id', id).order('debut'),
    ]);
    return _Vue(c, r[0].isEmpty ? null : r[0].first, r[1], r[2], r[3]);
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    if (mounted) _recharger();
  }

  Future<void> _changerStatut(_Vue v, String nouveau) async {
    final c = v.commande;
    try {
      if (nouveau == 'decoupe' && c['stock_deduit'] != true && v.facture != null) {
        await _deduireStock(c, v.facture!);
      }
      await supa.from('commandes').update({'statut': nouveau}).eq('id', c['id'] as String);
      if (!mounted) return;
      if (nouveau == 'prete') {
        final client = c['clients'] as Map<String, dynamic>;
        final prevenir = await confirmer(context, 'Commande prête',
            'Prévenir ${client['nom']} par WhatsApp que sa commande est prête ?', ok: 'Envoyer');
        if (prevenir && mounted) {
          final reste = v.facture == null ? 0 : num0(v.facture!['total']) - num0(v.facture!['montant_paye']);
          await ouvrirWhatsApp(
            context,
            client['telephone'] as String?,
            'Bonjour ${client['nom']}, votre commande ${c['numero']} est prête chez '
            '${Session.instance.atelier['nom']}. '
            '${reste > 0 ? 'Reste à payer : ${argent(reste)}. ' : ''}À bientôt !',
          );
        }
      }
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  /// Au passage en découpe : sortie de stock du tissu et des fournitures fournis par l'atelier.
  Future<void> _deduireStock(Map<String, dynamic> c, Map<String, dynamic> facture) async {
    final lignes = [
      for (final l in (facture['lignes'] as List? ?? const []))
        LigneDoc.depuisJson(Map<String, dynamic>.from(l as Map))
    ].where((l) => l.articleStockId != null && l.quantite > 0).toList();
    if (lignes.isEmpty) return;
    final ok = await confirmer(
      context,
      'Sortie de stock',
      'Déduire du stock pour la découpe :\n\n${lignes.map((l) => '• ${l.designation} : ${nombre(l.quantite)} ${l.unite}').join('\n')}',
      ok: 'Déduire',
    );
    if (!ok) return;
    await supa.from('stock_mouvements').insert([
      for (final l in lignes)
        {
          'atelier_id': Session.instance.atelierId,
          'article_id': l.articleStockId,
          'type': 'sortie',
          'quantite': l.quantite,
          'motif': 'Commande ${c['numero']}',
          'commande_id': c['id'],
        }
    ]);
    await supa.from('commandes').update({'stock_deduit': true}).eq('id', c['id'] as String);
  }

  Future<void> _changerLivraison(Map<String, dynamic> c) async {
    final d = await showDatePicker(
      context: context,
      initialDate: lireDate(c['date_livraison']) ?? aujourdhui(),
      firstDate: aujourdhui().subtract(const Duration(days: 365)),
      lastDate: aujourdhui().add(const Duration(days: 730)),
    );
    if (d == null) return;
    try {
      await supa.from('commandes').update({'date_livraison': isoDate(d)}).eq('id', c['id'] as String);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _assigner(Map<String, dynamic> c, String? userId) async {
    try {
      await supa.from('commandes').update({'assigne_a': userId}).eq('id', c['id'] as String);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  void _ficheDecoupe(Map<String, dynamic> c, ArticleCommande a) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfScreen(
        titre: 'Fiche de découpe',
        nomFichier: 'decoupe-${c['numero']}.pdf',
        construire: () => genererFicheDecoupePdf(
          calcul: a.calcul!,
          client: (c['clients'] as Map?)?['nom'] as String?,
          reference: '${c['numero']} · ${a.designation}',
        ),
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
        final c = v.commande;
        final client = c['clients'] as Map<String, dynamic>;
        final statut = c['statut'] as String;
        final idx = etapesProduction.indexOf(statut);
        final suivant = idx >= 0 && idx < etapesProduction.length - 1 ? etapesProduction[idx + 1] : null;
        final articles = [
          for (final a in (c['articles'] as List? ?? const []))
            ArticleCommande.depuisJson(Map<String, dynamic>.from(a as Map))
        ];
        final f = v.facture;
        final t = Theme.of(context);
        final nomsMembres = {for (final m in v.membres) m['user_id']: m['nom'] ?? roles[m['role']]};
        final assigne = c['assigne_a'] as String?;

        return Scaffold(
          appBar: AppBar(
            title: Text(c['numero'] as String? ?? 'Commande'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (s) => _changerStatut(v, s),
                itemBuilder: (_) => [
                  for (final e in libellesStatut.entries)
                    if (e.key != statut) PopupMenuItem(value: e.key, child: Text('Passer à : ${e.value}')),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Section(titre: 'Commande', children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person),
                title: Text(client['nom'] as String),
                subtitle: Text(client['telephone'] as String? ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _ouvrir(ClientDetailScreen(clientId: client['id'] as String)),
              ),
              Row(children: [
                Pastille(libellesStatut[statut] ?? statut, couleurStatut(statut)),
                const SizedBox(width: 8),
                if (c['priorite'] == 'urgente') const Pastille('URGENT', Colors.red),
                const Spacer(),
                Text('Commandée le ${dateCourte(lireDate(c['date_commande']))}', style: t.textTheme.bodySmall),
              ]),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text('Livraison : ${dateCourte(lireDate(c['date_livraison']))}'),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () => _changerLivraison(c),
              ),
              DropdownButtonFormField<String?>(
                initialValue: nomsMembres.containsKey(assigne) ? assigne : null,
                decoration: const InputDecoration(labelText: 'Couturier assigné', prefixIcon: Icon(Icons.engineering)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Personne')),
                  for (final m in v.membres)
                    DropdownMenuItem<String?>(
                      value: m['user_id'] as String,
                      child: Text('${m['nom'] ?? ''} (${roles[m['role']] ?? ''})'),
                    ),
                ],
                onChanged: (u) => _assigner(c, u),
              ),
              if (c['notes'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c['notes'] as String)),
            ]),
            Section(titre: 'Production', children: [
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (var i = 0; i < etapesProduction.length; i++)
                  Chip(
                    avatar: Icon(
                      statut == 'annulee' ? Icons.block : (i <= idx ? Icons.check_circle : Icons.radio_button_unchecked),
                      size: 18,
                      color: i <= idx ? couleurStatut(etapesProduction[i]) : null,
                    ),
                    label: Text(libellesStatut[etapesProduction[i]]!),
                  ),
              ]),
              if (suivant != null && statut != 'annulee') ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _changerStatut(v, suivant),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text('Étape suivante : ${libellesStatut[suivant]}'),
                ),
              ],
              if (v.historique.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Historique'),
                  children: [
                    for (final h in v.historique)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.circle, size: 12, color: couleurStatut(h['statut'] as String)),
                        title: Text(libellesStatut[h['statut']] ?? h['statut'] as String),
                        subtitle: Text('${dateHeure(lireDate(h['created_at'])!)}'
                            '${nomsMembres[h['par']] == null ? '' : ' · ${nomsMembres[h['par']]}'}'),
                      ),
                  ],
                ),
            ]),
            Section(titre: 'Vêtements', children: [
              for (final a in articles)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${a.designation} ×${a.quantite}', style: t.textTheme.titleMedium),
                      if (a.tissuSource == 'client')
                        Text('Tissu du client${a.metrage > 0 ? ' : ${quantiteTissu(a.metrage)} nécessaires' : ''}'),
                      if (a.tissuClient != null) Text('Déposé : ${a.tissuClient}', style: t.textTheme.bodySmall),
                      if (a.tissuSource == 'atelier') Text('Tissu atelier : ${a.tissuNom ?? ''} · ${quantiteTissu(a.metrage)}'),
                      if (a.calcul != null) ...[
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text('Découpe : ${a.calcul!.pieces.length} zones'),
                          children: [
                            for (final p in a.calcul!.pieces)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('${p.zone} ×${p.quantite}'),
                                subtitle: Text('${nombre(p.largeur)} × ${nombre(p.hauteur)} cm'
                                    '${p.tissu == TypeTissu.principal ? '' : ' · ${libellesTissu[p.tissu]}'}'),
                              ),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _ficheDecoupe(c, a),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Fiche de découpe'),
                        ),
                      ],
                    ]),
                  ),
                ),
              if (c['stock_deduit'] == true)
                Text('✓ Tissu et fournitures déduits du stock', style: t.textTheme.bodySmall),
            ]),
            Section(titre: 'Paiement', children: [
              if (f == null)
                const Text('Aucune facture liée.')
              else ...[
                Row(children: [
                  Expanded(child: Text('Facture ${f['numero']}')),
                  Pastille(statutsDocument[f['statut']] ?? '', couleurStatutDocument(f['statut'] as String)),
                ]),
                const SizedBox(height: 6),
                Text('Total : ${argent(num0(f['total']))}'),
                Text('Payé : ${argent(num0(f['montant_paye']))}'),
                Text('Reste : ${argent(num0(f['total']) - num0(f['montant_paye']))}',
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  if (f['statut'] != 'payee')
                    FilledButton.icon(
                      onPressed: () async {
                        if (await encaisser(context, f)) _recharger();
                      },
                      icon: const Icon(Icons.payments),
                      label: const Text('Encaisser'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _ouvrir(DocumentDetailScreen(documentId: f['id'] as String)),
                    icon: const Icon(Icons.receipt),
                    label: const Text('Voir la facture'),
                  ),
                ]),
              ],
            ]),
            Section(titre: 'Discussion interne', children: [
              const Text('Échangez avec l\'équipe sur cette commande : consignes de coupe, '
                  'retouches, questions… Le client ne voit pas ces messages.'),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => ouvrirDiscussionCommande(context, c),
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Ouvrir la discussion'),
              ),
            ]),
            Section(
              titre: 'Rendez-vous',
              action: TextButton.icon(
                onPressed: () => _ouvrir(RdvFormScreen(client: client, commande: c)),
                icon: const Icon(Icons.add),
                label: const Text('Planifier'),
              ),
              children: [
                if (v.rdvs.isEmpty) const Text('Aucun rendez-vous (essayage, livraison…).'),
                for (final r in v.rdvs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(iconeRdv(r['type'] as String)),
                    title: Text('${typesRdv[r['type']]} · ${dateHeure(lireDate(r['debut'])!)}'),
                    subtitle: Text(statutsRdv[r['statut']] ?? ''),
                    onTap: () => _ouvrir(RdvFormScreen(rdv: r)),
                  ),
              ],
            ),
          ]),
        );
      },
    );
  }
}
