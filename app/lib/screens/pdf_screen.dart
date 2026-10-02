import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Aperçu d'un PDF avec impression, enregistrement et partage (WhatsApp…).
class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key, required this.titre, required this.nomFichier, required this.construire});

  final String titre;
  final String nomFichier;
  final Future<Uint8List> Function() construire;

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  late final Future<Uint8List> _pdf = widget.construire();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titre)),
      body: PdfPreview(
        build: (_) => _pdf,
        pdfFileName: widget.nomFichier,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
