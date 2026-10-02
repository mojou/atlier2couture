import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Création / modification d'un client. Renvoie la ligne enregistrée.
class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key, this.client});

  final Map<String, dynamic>? client;

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: widget.client?['nom'] as String? ?? '');
  late final _tel = TextEditingController(text: widget.client?['telephone'] as String? ?? '');
  late final _email = TextEditingController(text: widget.client?['email'] as String? ?? '');
  late final _adresse = TextEditingController(text: widget.client?['adresse'] as String? ?? '');
  late final _notes = TextEditingController(text: widget.client?['notes'] as String? ?? '');
  late String? _sexe = widget.client?['sexe'] as String?;
  bool _occupe = false;

  String? _vide(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _occupe = true);
    try {
      final data = {
        'atelier_id': Session.instance.atelierId,
        'nom': _nom.text.trim(),
        'telephone': _vide(_tel),
        'email': _vide(_email),
        'adresse': _vide(_adresse),
        'notes': _vide(_notes),
        'sexe': _sexe,
      };
      final Map<String, dynamic> res;
      if (widget.client == null) {
        res = await supa.from('clients').insert(data).select().single();
      } else {
        res = await supa.from('clients').update(data).eq('id', widget.client!['id'] as String).select().single();
      }
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.client == null ? 'Nouveau client' : 'Modifier le client')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _nom,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nom et prénom *'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _tel,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Téléphone',
              helperText: 'Format international pour WhatsApp, ex : +225 07 00 00 00 00',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 'femme', label: Text('Femme')),
              ButtonSegment(value: 'homme', label: Text('Homme')),
              ButtonSegment(value: 'enfant', label: Text('Enfant')),
            ],
            selected: {if (_sexe != null) _sexe!},
            onSelectionChanged: (s) => setState(() => _sexe = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-mail'),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _adresse, decoration: const InputDecoration(labelText: 'Adresse')),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes (préférences, morphologie…)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _occupe ? null : _enregistrer,
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer'),
          ),
        ]),
      ),
    );
  }
}
