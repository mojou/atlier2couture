import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'document_detail_screen.dart';
import 'document_form_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  String _type = 'facture';
  bool _impayeesSeulement = false;
  late Future<List<Map<String, dynamic>>> _f = _charger();

  Future<List<Map<String, dynamic>>> _charger() {
    var q = supa
        .from('documents')
        .select('id, numero, type, statut, total, montant_paye, date_emission, clients(nom)')
        .eq('atelier_id', Session.instance.atelierId)
        .eq('type', _type);
    if (_type == 'facture' && _impayeesSeulement) q = q.inFilter('statut', ['impayee', 'partielle']);
    return q.order('created_at', ascending: false).limit(300);
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    if (mounted) _recharger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devis et factures')),
      floatingActionButton: _type == 'devis'
          ? FloatingActionButton.extended(
              onPressed: () => _ouvrir(const DocumentFormScreen(mode: 'devis')),
              icon: const Icon(Icons.add),
              label: const Text('Devis'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'facture', label: Text('Factures'), icon: Icon(Icons.receipt)),
              ButtonSegment(value: 'devis', label: Text('Devis'), icon: Icon(Icons.request_quote)),
            ],
            selected: {_type},
            onSelectionChanged: (s) {
              _type = s.first;
              _recharger();
            },
          ),
        ),
        if (_type == 'facture')
          SwitchListTile(
            title: const Text('Impayées uniquement'),
            value: _impayeesSeulement,
            onChanged: (v) {
              _impayeesSeulement = v;
              _recharger();
            },
          ),
        Expanded(
          child: AsyncVue<List<Map<String, dynamic>>>(
            future: _f,
            onReessayer: _recharger,
            builder: (context, docs) {
              if (docs.isEmpty) {
                return EtatVide(
                  icone: Icons.description_outlined,
                  message: _type == 'devis'
                      ? 'Aucun devis.'
                      : 'Aucune facture. Les factures sont créées avec les commandes.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final statut = d['statut'] as String;
                  final reste = num0(d['total']) - num0(d['montant_paye']);
                  return ListTile(
                    title: Text('${d['numero'] ?? ''} · ${(d['clients'] as Map?)?['nom'] ?? ''}'),
                    subtitle: Text('${dateCourte(lireDate(d['date_emission']))}'
                        '${_type == 'facture' && reste > 0 ? ' · reste ${argent(reste)}' : ''}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(argent(num0(d['total'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Pastille(statutsDocument[statut] ?? statut, couleurStatutDocument(statut)),
                      ],
                    ),
                    onTap: () => _ouvrir(DocumentDetailScreen(documentId: d['id'] as String)),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
