import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Enregistre un paiement sur une facture. Renvoie true si un paiement a été ajouté.
Future<bool> encaisser(BuildContext context, Map<String, dynamic> facture) async {
  final reste = num0(facture['total']) - num0(facture['montant_paye']);
  final montant = TextEditingController(text: nombreChamp(reste > 0 ? reste : null));
  final reference = TextEditingController();
  var mode = 'especes';
  final form = GlobalKey<FormState>();

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text('Encaisser · ${facture['numero'] ?? ''}'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reste à payer : ${argent(reste)}'),
              const SizedBox(height: 12),
              ChampNombre(controller: montant, label: 'Montant', suffixe: Session.instance.devise, obligatoire: true),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Mode de paiement'),
                items: [for (final e in modesPaiement.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => mode = v ?? 'especes'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reference,
                decoration: const InputDecoration(labelText: 'Référence (n° de transaction…)'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              final m = lireNombre(montant.text) ?? 0;
              if (m <= 0) return;
              Navigator.pop(c, true);
            },
            child: const Text('Encaisser'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return false;

  final m = lireNombre(montant.text) ?? 0;
  if (m > reste + 0.001 && context.mounted) {
    final continuer = await confirmer(context, 'Montant supérieur au reste',
        'Le montant (${argent(m)}) dépasse le reste à payer (${argent(reste)}). Continuer ?');
    if (!continuer) return false;
  }
  try {
    await supa.from('paiements').insert({
      'atelier_id': Session.instance.atelierId,
      'document_id': facture['id'],
      'montant': m,
      'mode': mode,
      'reference': reference.text.trim().isEmpty ? null : reference.text.trim(),
    });
    if (context.mounted) snack(context, 'Paiement de ${argent(m)} enregistré');
    return true;
  } catch (e) {
    if (context.mounted) snack(context, messageErreur(e), erreur: true);
    return false;
  }
}
