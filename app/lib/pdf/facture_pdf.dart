import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../calcul/devis.dart';
import '../calcul/lettres.dart';
import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import 'commun.dart';

/// Modèles de facture / devis proposés : code → (nom, description).
const modelesFacture = <String, (String, String)>{
  'classique': ('Classique', 'Sobre, bandeau de couleur sur le tableau'),
  'moderne': ('Moderne', 'En-tête coloré et blocs arrondis'),
  'elegant': ('Élégant', 'Police à empattements, mise en page centrée'),
  'minimal': ('Minimaliste', 'Noir et blanc, économise l\'encre'),
  'ticket': ('Ticket 80 mm', 'Pour imprimante thermique de caisse'),
};

String modeleValide(String? code) => modelesFacture.containsKey(code) ? code! : 'classique';

/// Facture ou devis au modèle choisi.
Future<Uint8List> genererDocumentPdf({
  required Map<String, dynamic> doc,
  required Map<String, dynamic> client,
  List<Map<String, dynamic>> paiements = const [],
  String? modele,
}) async {
  final atelier = Session.instance.atelier;
  final f = _Facture(
    atelier: atelier,
    doc: doc,
    client: client,
    paiements: paiements,
    logo: await chargerLogo(atelier),
    couleur: couleurAtelier(atelier),
  );
  final pdf = pw.Document(title: doc['numero'] as String?, author: txt(atelier['nom']));
  // Formule Gratuite : modèle Classique uniquement (avec mention de l'application).
  final choisi = Session.instance.offre.tousModeles
      ? modeleValide(modele ?? atelier['modele_facture'] as String?)
      : 'classique';
  switch (choisi) {
    case 'moderne':
      _moderne(pdf, f);
    case 'elegant':
      _elegant(pdf, f);
    case 'minimal':
      _minimal(pdf, f);
    case 'ticket':
      _ticket(pdf, f);
    default:
      _classique(pdf, f);
  }
  return pdf.save();
}

// ---------------------------------------------------------------------------
// Données communes
// ---------------------------------------------------------------------------

class _Total {
  const _Total(this.libelle, this.valeur, {this.fort = false});
  final String libelle;
  final String valeur;
  final bool fort;
}

class _Facture {
  _Facture({
    required this.atelier,
    required this.doc,
    required this.client,
    required this.paiements,
    required this.logo,
    required this.couleur,
  })  : lignes = [
          for (final l in (doc['lignes'] as List? ?? const []))
            LigneDoc.depuisJson(Map<String, dynamic>.from(l as Map))
        ],
        meta = Map<String, dynamic>.from((doc['meta'] as Map?) ?? const {});

  final Map<String, dynamic> atelier;
  final Map<String, dynamic> doc;
  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> paiements;
  final pw.ImageProvider? logo;
  final PdfColor couleur;
  final List<LigneDoc> lignes;
  final Map<String, dynamic> meta;

  bool get estFacture => doc['type'] == 'facture';
  String get titre => estFacture ? 'FACTURE' : 'DEVIS';
  String get numero => txt(doc['numero']);
  double get total => num0(doc['total']);
  double get paye => num0(doc['montant_paye']);
  double get acomptePct => num0(meta['acompte_pct']);

  String get nomAtelier => txt(atelier['nom']);

  List<String> get coordonnees => [
        txt(atelier['slogan']),
        [txt(atelier['adresse']), txt(atelier['ville']), txt(atelier['pays'])]
            .where((e) => e.isNotEmpty)
            .join(', '),
        [
          if (txt(atelier['telephone']).isNotEmpty) 'Tél : ${txt(atelier['telephone'])}',
          if (txt(atelier['email']).isNotEmpty) txt(atelier['email']),
        ].join('  ·  '),
        [
          if (txt(atelier['identifiant_fiscal']).isNotEmpty) 'NIF : ${txt(atelier['identifiant_fiscal'])}',
          if (txt(atelier['registre_commerce']).isNotEmpty) 'RCCM : ${txt(atelier['registre_commerce'])}',
        ].join('  ·  '),
      ].where((e) => e.isNotEmpty).toList();

  List<String> get infosDocument => [
        'N° $numero',
        'Date : ${dateCourte(lireDate(doc['date_emission']))}',
        if (doc['date_echeance'] != null)
          '${estFacture ? 'Échéance' : 'Valable jusqu\'au'} : ${dateCourte(lireDate(doc['date_echeance']))}',
        if (meta['date_livraison'] != null) 'Livraison prévue : ${dateCourte(lireDate(meta['date_livraison']))}',
      ];

  List<String> get infosClient => [
        if (txt(client['telephone']).isNotEmpty) 'Tél : ${txt(client['telephone'])}',
        if (txt(client['adresse']).isNotEmpty) txt(client['adresse']),
      ];

  List<_Total> get totaux => [
        _Total('Sous-total', argent(num0(doc['sous_total']))),
        if (num0(doc['remise_montant']) > 0) _Total('Remise', '- ${argent(num0(doc['remise_montant']))}'),
        if (num0(doc['taux_tva']) > 0)
          _Total('TVA (${nombre(num0(doc['taux_tva']))} %)', argent(num0(doc['montant_tva']))),
        _Total('TOTAL', argent(total), fort: true),
        if (estFacture) ...[
          _Total('Déjà payé', argent(paye)),
          _Total('Reste à payer', argent(total - paye), fort: true),
        ] else if (acomptePct > 0)
          _Total('Acompte à la commande (${nombre(acomptePct)} %)', argent(total * acomptePct / 100)),
      ];

  String get arrete => '${estFacture ? 'Arrêtée la présente facture' : 'Arrêté le présent devis'} à la somme de : '
      '${enLettres(total.round())} ${Session.instance.devise}.';

  List<String> get lignesPaiements => [
        for (final p in paiements)
          '${dateCourte(lireDate(p['paye_le']))} - ${modesPaiement[p['mode']] ?? p['mode']}'
              '${txt(p['reference']).isEmpty ? '' : ' (${txt(p['reference'])})'} : ${argent(num0(p['montant']))}'
      ];

  List<List<String>> get donneesTableau => [
        for (final l in lignes)
          [l.designation, nombre(l.quantite), l.unite, argent(l.prixUnitaire), argent(l.montant)]
      ];
}

const _entetesTableau = ['Désignation', 'Qté', 'Unité', 'Prix unitaire', 'Montant'];

const _alignements = {
  0: pw.Alignment.centerLeft,
  1: pw.Alignment.centerRight,
  2: pw.Alignment.center,
  3: pw.Alignment.centerRight,
  4: pw.Alignment.centerRight,
};

const _largeurs = {
  0: pw.FlexColumnWidth(4),
  1: pw.FlexColumnWidth(1),
  2: pw.FlexColumnWidth(1),
  3: pw.FlexColumnWidth(2),
  4: pw.FlexColumnWidth(2),
};

pw.Widget _logo(_Facture f, double taille) => f.logo == null
    ? pw.SizedBox()
    : pw.Container(width: taille, height: taille, child: pw.Image(f.logo!, fit: pw.BoxFit.contain));

pw.Widget _ligneTotal(_Total t, {PdfColor? couleur, double taille = 10}) {
  final style = pw.TextStyle(
    fontSize: t.fort ? taille + 2 : taille,
    fontWeight: t.fort ? pw.FontWeight.bold : pw.FontWeight.normal,
    color: t.fort ? couleur : null,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(children: [pw.Expanded(child: pw.Text(t.libelle, style: style)), pw.Text(t.valeur, style: style)]),
  );
}

/// Montant en lettres, paiements, notes, conditions et zone « bon pour accord ».
List<pw.Widget> _mentions(_Facture f, {PdfColor? couleurTitres, bool signatureDevis = true}) {
  final titre = pw.TextStyle(fontWeight: pw.FontWeight.bold, color: couleurTitres);
  return [
    pw.SizedBox(height: 12),
    pw.Text(f.arrete, style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
    if (f.estFacture && f.paiements.isNotEmpty) ...[
      pw.SizedBox(height: 14),
      pw.Text('Paiements reçus', style: titre),
      for (final l in f.lignesPaiements) pw.Text(l, style: const pw.TextStyle(fontSize: 10)),
    ],
    if (txt(f.doc['notes']).isNotEmpty) ...[
      pw.SizedBox(height: 14),
      pw.Text('Notes', style: titre),
      pw.Text(txt(f.doc['notes']), style: const pw.TextStyle(fontSize: 10)),
    ],
    if (txt(f.atelier['conditions_facture']).isNotEmpty) ...[
      pw.SizedBox(height: 14),
      pw.Text('Conditions', style: titre),
      pw.Text(txt(f.atelier['conditions_facture']), style: const pw.TextStyle(fontSize: 9)),
    ],
    if (!f.estFacture && signatureDevis) ...[
      pw.SizedBox(height: 28),
      pw.Row(children: [
        pw.Spacer(),
        pw.Container(
          width: 200,
          height: 70,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500)),
          child: pw.Text('Bon pour accord (date et signature du client)',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ),
      ]),
    ],
  ];
}

pw.Widget _piedDePage(pw.Context ctx, _Facture f, {bool centre = false}) => pw.Column(children: [
      if (!Session.instance.offre.tousModeles)
        pw.Text('Créé avec Atelier Couture - gestion d\'atelier de couture',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      pw.Divider(color: PdfColors.grey400),
      pw.Row(children: [
        pw.Expanded(
          child: pw.Text(txt(f.atelier['pied_facture']),
              textAlign: centre ? pw.TextAlign.center : pw.TextAlign.left,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ),
        pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ]),
    ]);

// ---------------------------------------------------------------------------
// 1. Classique
// ---------------------------------------------------------------------------

void _classique(pw.Document pdf, _Facture f) {
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    footer: (ctx) => _piedDePage(ctx, f),
    build: (ctx) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (f.logo != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 12), child: _logo(f, 70)),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(f.nomAtelier, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: f.couleur)),
            for (final l in f.coordonnees) pw.Text(l, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(f.titre, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: f.couleur)),
          for (final l in f.infosDocument) pw.Text(l, style: const pw.TextStyle(fontSize: 10)),
        ]),
      ]),
      pw.SizedBox(height: 20),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(f.estFacture ? 'Facturé à' : 'Client', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text(txt(f.client['nom']), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          for (final l in f.infosClient) pw.Text(l),
        ]),
      ),
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: _entetesTableau,
        data: f.donneesTableau,
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
        headerDecoration: pw.BoxDecoration(color: f.couleur),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignments: _alignements,
        columnWidths: _largeurs,
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        border: null,
      ),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        pw.Spacer(),
        pw.SizedBox(
          width: 240,
          child: pw.Column(children: [
            for (final t in f.totaux) ...[
              if (t.libelle == 'TOTAL') pw.Divider(),
              _ligneTotal(t, couleur: t.libelle == 'TOTAL' ? f.couleur : null),
            ],
          ]),
        ),
      ]),
      ..._mentions(f),
    ],
  ));
}

// ---------------------------------------------------------------------------
// 2. Moderne : en-tête coloré, blocs arrondis
// ---------------------------------------------------------------------------

void _moderne(pw.Document pdf, _Facture f) {
  final clair = teinte(f.couleur, 0.10);
  pw.Widget bloc(String titre, List<pw.Widget> contenu) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: clair, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(titre.toUpperCase(),
                style: pw.TextStyle(fontSize: 8, color: f.couleur, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
            pw.SizedBox(height: 4),
            ...contenu,
          ]),
        ),
      );

  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: (ctx) => _piedDePage(ctx, f),
    build: (ctx) => [
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(color: f.couleur, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Row(children: [
          if (f.logo != null)
            pw.Container(
              margin: const pw.EdgeInsets.only(right: 12),
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(8)),
              child: _logo(f, 56),
            ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(f.nomAtelier,
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              if (txt(f.atelier['slogan']).isNotEmpty)
                pw.Text(txt(f.atelier['slogan']), style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(f.titre,
                style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 2)),
            pw.Text('N° ${f.numero}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
          ]),
        ]),
      ),
      pw.SizedBox(height: 6),
      pw.Text(f.coordonnees.skip(txt(f.atelier['slogan']).isEmpty ? 0 : 1).join('  ·  '),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      pw.SizedBox(height: 16),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        bloc(f.estFacture ? 'Facturé à' : 'Client', [
          pw.Text(txt(f.client['nom']), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          for (final l in f.infosClient) pw.Text(l, style: const pw.TextStyle(fontSize: 10)),
        ]),
        pw.SizedBox(width: 12),
        bloc('Détails', [for (final l in f.infosDocument.skip(1)) pw.Text(l, style: const pw.TextStyle(fontSize: 10))]),
      ]),
      pw.SizedBox(height: 18),
      pw.TableHelper.fromTextArray(
        headers: _entetesTableau,
        data: f.donneesTableau,
        headerStyle: pw.TextStyle(color: f.couleur, fontWeight: pw.FontWeight.bold, fontSize: 10),
        headerDecoration: pw.BoxDecoration(color: clair),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignments: _alignements,
        columnWidths: _largeurs,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      pw.SizedBox(height: 14),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Spacer(),
        pw.SizedBox(
          width: 250,
          child: pw.Column(children: [
            for (final t in f.totaux)
              if (t.libelle == 'TOTAL')
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 4),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: pw.BoxDecoration(color: f.couleur, borderRadius: pw.BorderRadius.circular(6)),
                  child: pw.Row(children: [
                    pw.Expanded(
                      child: pw.Text('TOTAL',
                          style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    ),
                    pw.Text(t.valeur,
                        style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  ]),
                )
              else
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                  child: _ligneTotal(t, couleur: f.couleur),
                ),
          ]),
        ),
      ]),
      ..._mentions(f, couleurTitres: f.couleur),
    ],
  ));
}

// ---------------------------------------------------------------------------
// 3. Élégant : police à empattements, centré, filets fins
// ---------------------------------------------------------------------------

void _elegant(pw.Document pdf, _Facture f) {
  final theme = pw.ThemeData.withFont(
    base: pw.Font.times(),
    bold: pw.Font.timesBold(),
    italic: pw.Font.timesItalic(),
    boldItalic: pw.Font.timesBoldItalic(),
  );
  final filet = pw.Container(height: 0.8, color: f.couleur);
  pw.Widget etiquette(String s) => pw.Text(s.toUpperCase(),
      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, letterSpacing: 1.5));

  pdf.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40), theme: theme),
    footer: (ctx) => pw.Column(children: [
      filet,
      pw.SizedBox(height: 4),
      pw.Text(f.coordonnees.join('  ·  '),
          textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      if (txt(f.atelier['pied_facture']).isNotEmpty)
        pw.Text(txt(f.atelier['pied_facture']),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: f.couleur)),
    ]),
    build: (ctx) => [
      pw.Center(
        child: pw.Column(children: [
          if (f.logo != null) _logo(f, 64),
          pw.SizedBox(height: 6),
          pw.Text(f.nomAtelier.toUpperCase(),
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, letterSpacing: 3, color: f.couleur)),
          if (txt(f.atelier['slogan']).isNotEmpty)
            pw.Text(txt(f.atelier['slogan']), style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic)),
        ]),
      ),
      pw.SizedBox(height: 14),
      filet,
      pw.SizedBox(height: 2),
      filet,
      pw.SizedBox(height: 14),
      pw.Center(
        child: pw.Text('${f.estFacture ? 'Facture' : 'Devis'} n° ${f.numero}',
            style: pw.TextStyle(fontSize: 16, fontStyle: pw.FontStyle.italic)),
      ),
      pw.SizedBox(height: 16),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            etiquette(f.estFacture ? 'Facturé à' : 'Client'),
            pw.Text(txt(f.client['nom']), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            for (final l in f.infosClient) pw.Text(l, style: const pw.TextStyle(fontSize: 10)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          etiquette('Références'),
          for (final l in f.infosDocument.skip(1)) pw.Text(l, style: const pw.TextStyle(fontSize: 10)),
        ]),
      ]),
      pw.SizedBox(height: 20),
      pw.TableHelper.fromTextArray(
        headers: _entetesTableau,
        data: f.donneesTableau,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: f.couleur),
        cellStyle: const pw.TextStyle(fontSize: 11),
        cellAlignments: _alignements,
        columnWidths: _largeurs,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        border: pw.TableBorder(
          top: pw.BorderSide(color: f.couleur, width: 0.8),
          bottom: pw.BorderSide(color: f.couleur, width: 0.8),
          horizontalInside: const pw.BorderSide(color: PdfColors.grey300, width: 0.4),
        ),
      ),
      pw.SizedBox(height: 14),
      pw.Row(children: [
        pw.Spacer(),
        pw.SizedBox(
          width: 240,
          child: pw.Column(children: [
            for (final t in f.totaux) ...[
              if (t.libelle == 'TOTAL') pw.Container(height: 0.6, color: f.couleur, margin: const pw.EdgeInsets.symmetric(vertical: 3)),
              _ligneTotal(t, couleur: f.couleur, taille: 11),
            ],
          ]),
        ),
      ]),
      ..._mentions(f, couleurTitres: f.couleur),
      pw.SizedBox(height: 30),
      pw.Row(children: [
        pw.Spacer(),
        pw.Column(children: [
          pw.Container(width: 160, height: 0.5, color: PdfColors.grey600),
          pw.SizedBox(height: 3),
          pw.Text('La direction', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
        ]),
      ]),
    ],
  ));
}

// ---------------------------------------------------------------------------
// 4. Minimaliste : noir et blanc
// ---------------------------------------------------------------------------

void _minimal(pw.Document pdf, _Facture f) {
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (ctx) => _piedDePage(ctx, f),
    build: (ctx) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (f.logo != null) ...[_logo(f, 40), pw.SizedBox(height: 6)],
            pw.Text(f.nomAtelier, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            for (final l in f.coordonnees) pw.Text(l, style: const pw.TextStyle(fontSize: 8)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(f.titre, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 4)),
          for (final l in f.infosDocument) pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
        ]),
      ]),
      pw.SizedBox(height: 24),
      pw.Text(f.estFacture ? 'Facturé à' : 'Client', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      pw.Text(txt(f.client['nom']), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      for (final l in f.infosClient) pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 18),
      pw.TableHelper.fromTextArray(
        headers: _entetesTableau,
        data: f.donneesTableau,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: _alignements,
        columnWidths: _largeurs,
        border: const pw.TableBorder(
          top: pw.BorderSide(width: 1),
          bottom: pw.BorderSide(width: 1),
          horizontalInside: pw.BorderSide(width: 0.3, color: PdfColors.grey500),
        ),
        headerDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 1)),
        ),
      ),
      pw.SizedBox(height: 10),
      pw.Row(children: [
        pw.Spacer(),
        pw.SizedBox(width: 220, child: pw.Column(children: [for (final t in f.totaux) _ligneTotal(t, taille: 9)])),
      ]),
      ..._mentions(f),
    ],
  ));
}

// ---------------------------------------------------------------------------
// 5. Ticket de caisse 80 mm
// ---------------------------------------------------------------------------

void _ticket(pw.Document pdf, _Facture f) {
  const petit = pw.TextStyle(fontSize: 7);
  const normal = pw.TextStyle(fontSize: 8);
  final gras = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  pw.Widget tirets() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Divider(height: 1, borderStyle: pw.BorderStyle.dashed, color: PdfColors.black),
      );
  pw.Widget ligne(String a, String b, {pw.TextStyle? style}) => pw.Row(children: [
        pw.Expanded(child: pw.Text(a, style: style ?? normal)),
        pw.Text(b, style: style ?? normal),
      ]);

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.roll80.copyWith(
      marginLeft: 3 * PdfPageFormat.mm,
      marginRight: 3 * PdfPageFormat.mm,
      marginTop: 4 * PdfPageFormat.mm,
      marginBottom: 6 * PdfPageFormat.mm,
    ),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      if (f.logo != null) pw.Center(child: _logo(f, 42)),
      pw.Text(f.nomAtelier, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      for (final l in f.coordonnees) pw.Text(l, textAlign: pw.TextAlign.center, style: petit),
      tirets(),
      pw.Text('${f.titre} ${f.numero}', textAlign: pw.TextAlign.center, style: gras),
      for (final l in f.infosDocument.skip(1)) pw.Text(l, textAlign: pw.TextAlign.center, style: petit),
      pw.Text('Client : ${txt(f.client['nom'])}', textAlign: pw.TextAlign.center, style: normal),
      tirets(),
      for (final l in f.lignes) ...[
        pw.Text(l.designation, style: normal),
        ligne('  ${nombre(l.quantite)} ${l.unite} x ${argent(l.prixUnitaire)}', argent(l.montant)),
      ],
      tirets(),
      for (final t in f.totaux) ligne(t.libelle, t.valeur, style: t.fort ? gras : normal),
      pw.SizedBox(height: 4),
      pw.Text(f.arrete, style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)),
      if (f.estFacture && f.paiements.isNotEmpty) ...[
        tirets(),
        for (final l in f.lignesPaiements) pw.Text(l, style: petit),
      ],
      if (txt(f.doc['notes']).isNotEmpty) ...[tirets(), pw.Text(txt(f.doc['notes']), style: petit)],
      tirets(),
      pw.Text(txt(f.atelier['pied_facture']).isEmpty ? 'Merci de votre visite !' : txt(f.atelier['pied_facture']),
          textAlign: pw.TextAlign.center, style: gras),
    ]),
  ));
}
