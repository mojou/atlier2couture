import 'package:flutter/material.dart';

import '../calcul/devis.dart';
import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../services/export_csv.dart';

/// Export des données de l'atelier en fichiers CSV (ouverts par Excel).
class ExportsScreen extends StatefulWidget {
  const ExportsScreen({super.key});

  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends State<ExportsScreen> {
  String? _enCours;

  String get _a => Session.instance.atelierId;

  String _date(dynamic v) => v == null ? '' : dateCourte(lireDate(v));

  Future<void> _exporter(String code, Future<(List<String>, List<List<Object?>>)> Function() donnees) async {
    setState(() => _enCours = code);
    try {
      final (entetes, lignes) = await donnees();
      final nom = '${code}_${isoDate(DateTime.now())}.csv';
      await partagerFichier(construireCsv(entetes, lignes), nom);
      if (mounted) snack(context, '${lignes.length} ligne(s) exportée(s) : $nom');
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  Future<(List<String>, List<List<Object?>>)> _clients() async {
    final rows = await supa.from('clients').select().eq('atelier_id', _a).order('nom');
    return (
      ['Nom', 'Téléphone', 'E-mail', 'Sexe', 'Adresse', 'Notes', 'Créé le'],
      [for (final c in rows) [c['nom'], c['telephone'], c['email'], c['sexe'], c['adresse'], c['notes'], _date(c['created_at'])]],
    );
  }

  Future<(List<String>, List<List<Object?>>)> _commandes() async {
    final rows = await supa
        .from('commandes')
        .select('*, clients(nom, telephone)')
        .eq('atelier_id', _a)
        .order('created_at', ascending: false);
    return (
      ['Numéro', 'Client', 'Téléphone', 'Vêtements', 'Statut', 'Priorité', 'Commandée le', 'Livraison', 'Total'],
      [
        for (final c in rows)
          [
            c['numero'],
            (c['clients'] as Map?)?['nom'],
            (c['clients'] as Map?)?['telephone'],
            (c['articles'] as List? ?? const []).map((a) => '${(a as Map)['designation']} x${a['quantite']}').join(', '),
            libellesStatut[c['statut']] ?? c['statut'],
            c['priorite'],
            _date(c['date_commande']),
            _date(c['date_livraison']),
            num0(c['total']),
          ]
      ],
    );
  }

  Future<(List<String>, List<List<Object?>>)> _documents() async {
    final rows = await supa
        .from('documents')
        .select('*, clients(nom)')
        .eq('atelier_id', _a)
        .order('date_emission', ascending: false);
    return (
      ['Type', 'Numéro', 'Client', 'Date', 'Échéance', 'Statut', 'Sous-total', 'Remise', 'TVA', 'Total', 'Payé', 'Reste', 'Détail'],
      [
        for (final d in rows)
          [
            d['type'] == 'facture' ? 'Facture' : 'Devis',
            d['numero'],
            (d['clients'] as Map?)?['nom'],
            _date(d['date_emission']),
            _date(d['date_echeance']),
            statutsDocument[d['statut']] ?? d['statut'],
            num0(d['sous_total']),
            num0(d['remise_montant']),
            num0(d['montant_tva']),
            num0(d['total']),
            num0(d['montant_paye']),
            num0(d['total']) - num0(d['montant_paye']),
            (d['lignes'] as List? ?? const [])
                .map((l) => LigneDoc.depuisJson(Map<String, dynamic>.from(l as Map)))
                .map((l) => '${l.designation} (${nombre(l.quantite)} ${l.unite})')
                .join(', '),
          ]
      ],
    );
  }

  Future<(List<String>, List<List<Object?>>)> _paiements() async {
    final rows = await supa
        .from('paiements')
        .select('*, documents(numero, clients(nom))')
        .eq('atelier_id', _a)
        .order('paye_le', ascending: false);
    return (
      ['Date', 'Facture', 'Client', 'Mode', 'Référence', 'Montant'],
      [
        for (final p in rows)
          [
            _date(p['paye_le']),
            (p['documents'] as Map?)?['numero'],
            ((p['documents'] as Map?)?['clients'] as Map?)?['nom'],
            modesPaiement[p['mode']] ?? p['mode'],
            p['reference'],
            num0(p['montant']),
          ]
      ],
    );
  }

  Future<(List<String>, List<List<Object?>>)> _depenses() async {
    final rows = await supa.from('depenses').select().eq('atelier_id', _a).order('date', ascending: false);
    return (
      ['Date', 'Catégorie', 'Libellé', 'Mode', 'Montant'],
      [
        for (final d in rows)
          [_date(d['date']), categoriesDepense[d['categorie']] ?? d['categorie'], d['libelle'], modesPaiement[d['mode']] ?? d['mode'], num0(d['montant'])]
      ],
    );
  }

  Future<(List<String>, List<List<Object?>>)> _stock() async {
    final rows = await supa.from('stock_articles').select().eq('atelier_id', _a).order('categorie').order('nom');
    return (
      ['Catégorie', 'Article', 'Référence', 'Couleur', 'Quantité', 'Unité', 'Seuil', "Prix d'achat", 'Prix de vente', 'Valeur du stock'],
      [
        for (final s in rows)
          [
            categoriesStock[s['categorie']] ?? s['categorie'],
            s['nom'],
            s['reference'],
            s['couleur'],
            num0(s['quantite']),
            s['unite'],
            num0(s['seuil_alerte']),
            num0(s['prix_achat']),
            num0(s['prix_vente']),
            num0(s['quantite']) * num0(s['prix_achat']),
          ]
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final exports = [
      ('clients', 'Clients', Icons.people_outline, _clients),
      ('commandes', 'Commandes', Icons.receipt_long_outlined, _commandes),
      ('devis_factures', 'Devis et factures', Icons.description_outlined, _documents),
      ('paiements', 'Paiements reçus', Icons.payments_outlined, _paiements),
      ('depenses', 'Dépenses', Icons.money_off, _depenses),
      ('stock', 'Stock', Icons.inventory_2_outlined, _stock),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Exporter mes données')),
      body: ListView(children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Chaque export crée un fichier CSV qui s\'ouvre dans Excel ou Google Sheets. '
              'Sur téléphone, vous pouvez l\'envoyer par WhatsApp ou e-mail à votre comptable.'),
        ),
        for (final (code, titre, icone, fonction) in exports)
          ListTile(
            leading: Icon(icone),
            title: Text(titre),
            trailing: _enCours == code
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            onTap: _enCours != null ? null : () => _exporter(code, fonction),
          ),
      ]),
    );
  }
}
