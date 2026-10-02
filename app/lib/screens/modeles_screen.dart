import 'package:flutter/material.dart';

import '../calcul/vetements.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Catalogue des modèles de l'atelier avec leur prix de façon.
class ModelesScreen extends StatefulWidget {
  const ModelesScreen({super.key, this.modeSelection = false});

  final bool modeSelection;

  @override
  State<ModelesScreen> createState() => _ModelesScreenState();
}

class _ModelesScreenState extends State<ModelesScreen> {
  late Future<List<Map<String, dynamic>>> _f = _charger();

  Future<List<Map<String, dynamic>>> _charger() =>
      supa.from('modeles').select().eq('atelier_id', Session.instance.atelierId).order('nom');

  void _recharger() => setState(() => _f = _charger());

  Future<void> _editer([Map<String, dynamic>? m]) async {
    final nom = TextEditingController(text: m?['nom'] as String? ?? '');
    final prix = TextEditingController(text: nombreChamp(m?['prix_facon'] as num?));
    final description = TextEditingController(text: m?['description'] as String? ?? '');
    String? type = typeParCode(m?['type_vetement'] as String?)?.code;
    final form = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(m == null ? 'Nouveau modèle' : 'Modifier le modèle'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: nom,
                  decoration: const InputDecoration(labelText: 'Nom du modèle *', hintText: 'ex : Grand boubou brodé'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type de vêtement'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('—')),
                    for (final t in typesVetements) DropdownMenuItem<String?>(value: t.code, child: Text(t.nom)),
                  ],
                  onChanged: (v) => setState(() => type = v),
                ),
                const SizedBox(height: 12),
                ChampNombre(controller: prix, label: 'Prix de façon', suffixe: Session.instance.devise, obligatoire: true),
                const SizedBox(height: 12),
                TextFormField(
                  controller: description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(c, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final data = {
      'atelier_id': Session.instance.atelierId,
      'nom': nom.text.trim(),
      'type_vetement': type,
      'prix_facon': lireNombre(prix.text) ?? 0,
      'description': description.text.trim().isEmpty ? null : description.text.trim(),
    };
    try {
      if (m == null) {
        await supa.from('modeles').insert(data);
      } else {
        await supa.from('modeles').update(data).eq('id', m['id'] as String);
      }
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _supprimer(Map<String, dynamic> m) async {
    if (!await confirmer(context, 'Supprimer', 'Supprimer le modèle « ${m['nom']} » ?', ok: 'Supprimer')) return;
    try {
      await supa.from('modeles').delete().eq('id', m['id'] as String);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.modeSelection ? 'Choisir un modèle' : 'Catalogue de modèles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editer(),
        icon: const Icon(Icons.add),
        label: const Text('Modèle'),
      ),
      body: AsyncVue<List<Map<String, dynamic>>>(
        future: _f,
        onReessayer: _recharger,
        builder: (context, modeles) {
          if (modeles.isEmpty) {
            return const EtatVide(
              icone: Icons.style_outlined,
              message: 'Ajoutez vos modèles et leur prix de façon : ils seront proposés dans les devis.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: modeles.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = modeles[i];
              return ListTile(
                title: Text(m['nom'] as String),
                subtitle: Text([
                  if (typeParCode(m['type_vetement'] as String?) != null) typeParCode(m['type_vetement'] as String?)!.nom,
                  if (m['description'] != null) m['description'] as String,
                ].join(' · ')),
                trailing: widget.modeSelection
                    ? Text(argent(num0(m['prix_facon'])))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(argent(num0(m['prix_facon']))),
                        if (Session.instance.estGestionnaire)
                          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _supprimer(m)),
                      ]),
                onTap: () {
                  if (widget.modeSelection) {
                    Navigator.pop(context, m);
                  } else {
                    _editer(m);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
