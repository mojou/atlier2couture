import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../pdf/facture_pdf.dart';
import 'abonnement_screen.dart';

/// Aperçu d'une facture ou d'un devis avec choix du modèle de mise en page.
class FacturePdfScreen extends StatefulWidget {
  const FacturePdfScreen({super.key, required this.doc, required this.client, this.paiements = const []});

  final Map<String, dynamic> doc;
  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> paiements;

  @override
  State<FacturePdfScreen> createState() => _FacturePdfScreenState();
}

class _FacturePdfScreenState extends State<FacturePdfScreen> {
  bool get _tousModeles => Session.instance.offre.tousModeles;
  late String _modele = _tousModeles ? modeleValide(Session.instance.modeleFacture) : 'classique';
  final _cache = <String, Future<Uint8List>>{};

  Future<Uint8List> _pdf(String modele) => _cache.putIfAbsent(
        modele,
        () => genererDocumentPdf(
          doc: widget.doc,
          client: widget.client,
          paiements: widget.paiements,
          modele: modele,
        ),
      );

  Future<void> _definirParDefaut() async {
    try {
      final a = await supa
          .from('ateliers')
          .update({'modele_facture': _modele})
          .eq('id', Session.instance.atelierId)
          .select()
          .single();
      Session.instance.majAtelier(a);
      if (mounted) {
        setState(() {});
        snack(context, 'Modèle « ${modelesFacture[_modele]!.$1} » utilisé par défaut');
      }
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parDefaut = _modele == modeleValide(Session.instance.modeleFacture);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.doc['numero'] as String? ?? 'Document'),
        actions: [
          if (Session.instance.estGestionnaire && !parDefaut)
            TextButton.icon(
              onPressed: _definirParDefaut,
              icon: const Icon(Icons.star_outline),
              label: const Text('Par défaut'),
            ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final e in modelesFacture.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: e.value.$2,
                    child: ChoiceChip(
                      avatar: !_tousModeles && e.key != 'classique'
                          ? const Icon(Icons.lock_outline, size: 16)
                          : e.key == modeleValide(Session.instance.modeleFacture)
                              ? const Icon(Icons.star, size: 16)
                              : null,
                      label: Text(e.value.$1),
                      selected: _modele == e.key,
                      onSelected: (_) {
                        if (_tousModeles || e.key == 'classique') {
                          setState(() => _modele = e.key);
                        } else {
                          proposerFormule(context,
                              'Les 5 modèles de facture, sans mention de l\'application, sont inclus à partir de la formule Standard.');
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: PdfPreview(
            key: ValueKey(_modele),
            build: (_) => _pdf(_modele),
            pdfFileName: '${widget.doc['numero'] ?? 'document'}.pdf',
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
          ),
        ),
      ]),
    );
  }
}
