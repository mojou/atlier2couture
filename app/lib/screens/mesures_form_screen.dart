import 'package:flutter/material.dart';

import '../calcul/mesures.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Nouvelle prise de mesures (l'historique est conservé).
class MesuresFormScreen extends StatefulWidget {
  const MesuresFormScreen({super.key, required this.clientId, required this.nomClient, this.initiales});

  final String clientId;
  final String nomClient;
  final Map<String, double>? initiales;

  @override
  State<MesuresFormScreen> createState() => _MesuresFormScreenState();
}

class _MesuresFormScreenState extends State<MesuresFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c = {
    for (final d in mesuresDefs) d.cle: TextEditingController(text: nombreChamp(widget.initiales?[d.cle])),
  };
  final _note = TextEditingController();
  bool _occupe = false;

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    final valeurs = <String, double>{
      for (final e in _c.entries)
        if ((lireNombre(e.value.text) ?? 0) > 0) e.key: lireNombre(e.value.text)!,
    };
    if (valeurs.isEmpty) {
      snack(context, 'Saisissez au moins une mesure', erreur: true);
      return;
    }
    final alertes = valeursInhabituelles(Mesures(valeurs));
    if (alertes.isNotEmpty) {
      final ok = await confirmer(context, 'Vérifiez ces mesures', alertes.join('\n\n'), ok: 'Enregistrer quand même');
      if (!ok) return;
    }
    setState(() => _occupe = true);
    try {
      await supa.from('mesures').insert({
        'atelier_id': Session.instance.atelierId,
        'client_id': widget.clientId,
        'valeurs': valeurs,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupes = <String, List<MesureDef>>{};
    for (final d in mesuresDefs) {
      groupes.putIfAbsent(d.groupe, () => []).add(d);
    }
    return Scaffold(
      appBar: AppBar(title: Text('Mesures · ${widget.nomClient}')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Toutes les mesures sont en centimètres. Laissez vide ce qui ne sert pas.'),
          const SizedBox(height: 12),
          for (final g in groupes.entries) ...[
            Text(g.key, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final d in g.value)
                SizedBox(
                  width: 170,
                  child: ChampNombre(controller: _c[d.cle]!, label: d.libelle, suffixe: 'cm', aide: d.aide),
                ),
            ]),
            const SizedBox(height: 20),
          ],
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Remarque (posture, épaule tombante…)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _occupe ? null : _enregistrer,
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer les mesures'),
          ),
        ]),
      ),
    );
  }
}
