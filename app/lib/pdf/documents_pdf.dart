import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../calcul/calcul.dart';
import '../core/format.dart';
import '../core/session.dart';
import 'commun.dart';

export 'facture_pdf.dart';

const _couleursPieces = [
  PdfColors.amber100, PdfColors.lightBlue100, PdfColors.lightGreen100, PdfColors.pink100,
  PdfColors.deepPurple100, PdfColors.orange100, PdfColors.teal100, PdfColors.indigo100,
];

/// Fiche de découpe pour le couturier : mesures, pièces zone par zone et plans de coupe.
Future<Uint8List> genererFicheDecoupePdf({
  required CalculSauvegarde calcul,
  String? client,
  String? reference,
}) async {
  final atelier = Session.instance.atelier;
  final couleur = couleurAtelier(atelier);
  final resultats = calcul.recalculer();
  final unite = calcul.unite;

  final pdf = pw.Document(title: 'Fiche de découpe');
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (ctx) => [
      pw.Text('FICHE DE DÉCOUPE',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: couleur)),
      pw.Text([
        txt(atelier['nom']),
        if (reference != null) reference,
        if (client != null) 'Client : $client',
        'Le ${dateCourte(DateTime.now())}',
      ].join('  ·  ')),
      pw.Text('Vêtements : ${calcul.resume}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 12),
      if (calcul.mesures.isNotEmpty) ...[
        pw.Text('Mesures du client (cm)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Wrap(spacing: 14, runSpacing: 2, children: [
          for (final d in mesuresDefs)
            if ((calcul.mesures[d.cle] ?? 0) > 0)
              pw.Text('${d.libelle} : ${nombre(calcul.mesures[d.cle])}',
                  style: const pw.TextStyle(fontSize: 10)),
        ]),
        pw.SizedBox(height: 12),
      ],
      for (final r in resultats.values) ...[
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          color: PdfColors.grey200,
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Text('${libellesTissu[r.tissu]} - largeur ${nombre(r.largeurTissu)} cm',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text('${nombre(r.quantite(unite))} $unite',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: couleur)),
          ]),
        ),
        pw.Text('Longueur de coupe ${nombre(r.longueurCoupe, max: 0)} cm + marge ${nombre(r.marge, max: 0)} cm'
            '  ·  tissu utilisé à ${nombre(r.rendement * 100, max: 0)} %',
            style: const pw.TextStyle(fontSize: 9)),
        for (final a in r.avertissements)
          pw.Text('Attention : $a', style: const pw.TextStyle(fontSize: 9, color: PdfColors.red800)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: ['Zone', 'Qté', 'Largeur (cm)', 'Hauteur (cm)', 'Remarque'],
          data: [
            for (final p in calcul.pieces.where((p) => p.tissu == r.tissu))
              [p.zone, '${p.quantite}', nombre(p.largeur), nombre(p.hauteur),
                [if (p.pivotable) 'peut pivoter', if (p.note != null) p.note!].join(' · ')]
          ],
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {1: pw.Alignment.center, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
        ),
        pw.SizedBox(height: 12),
      ],
      pw.Text('Mesures de coupe : coutures (1,5 cm par côté) et ourlets compris. '
          'Hauteur = sens du droit fil (longueur du tissu).',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    ],
  ));

  // Un plan de coupe par tissu.
  for (final r in resultats.values) {
    if (r.placements.isEmpty) continue;
    const largeurDispo = 539.0;
    const hauteurDispo = 700.0;
    final echelle = [largeurDispo / r.largeurTissu, hauteurDispo / r.longueurCoupe]
        .reduce((a, b) => a < b ? a : b);
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Plan de coupe - ${libellesTissu[r.tissu]}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: couleur)),
        pw.Text('Largeur ${nombre(r.largeurTissu)} cm (en travers) × longueur ${nombre(r.longueurCoupe, max: 0)} cm',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
        pw.Container(
          width: r.largeurTissu * echelle,
          height: r.longueurCoupe * echelle,
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey600),
          ),
          child: pw.Stack(children: [
            for (var i = 0; i < r.placements.length; i++)
              pw.Positioned(
                left: r.placements[i].x * echelle,
                top: r.placements[i].y * echelle,
                child: pw.Container(
                  width: r.placements[i].largeur * echelle,
                  height: r.placements[i].hauteur * echelle,
                  padding: const pw.EdgeInsets.all(1),
                  decoration: pw.BoxDecoration(
                    color: _couleursPieces[i % _couleursPieces.length],
                    border: pw.Border.all(color: PdfColors.grey800, width: 0.5),
                  ),
                  child: r.placements[i].largeur * echelle > 6 && r.placements[i].hauteur * echelle > 6
                      ? pw.FittedBox(
                          fit: pw.BoxFit.scaleDown,
                          child: pw.Text(
                            '${r.placements[i].libelle}\n${nombre(r.placements[i].largeur)} x ${nombre(r.placements[i].hauteur)}',
                            style: const pw.TextStyle(fontSize: 7),
                            textAlign: pw.TextAlign.center,
                          ),
                        )
                      : pw.SizedBox(),
                ),
              ),
          ]),
        ),
      ]),
    ));
  }
  return pdf.save();
}
