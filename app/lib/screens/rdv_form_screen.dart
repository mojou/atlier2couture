import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../services/alarmes.dart';
import 'abonnement_screen.dart';
import 'clients_screen.dart';

/// Création / modification d'un rendez-vous et de son alarme musicale.
class RdvFormScreen extends StatefulWidget {
  const RdvFormScreen({super.key, this.rdv, this.client, this.commande});

  final Map<String, dynamic>? rdv;
  final Map<String, dynamic>? client;
  final Map<String, dynamic>? commande;

  @override
  State<RdvFormScreen> createState() => _RdvFormScreenState();
}

class _RdvFormScreenState extends State<RdvFormScreen> {
  static const _delais = {0: 'À l\'heure', 10: '10 min avant', 30: '30 min avant', 60: '1 h avant', 120: '2 h avant', 1440: 'La veille'};

  Map<String, dynamic>? _client;
  String? _commandeId;
  String? _commandeNumero;
  String _type = 'essayage';
  late DateTime _date;
  late TimeOfDay _heure;
  int _duree = 30;
  final _note = TextEditingController();
  bool _alarme = true;

  /// Délai en minutes avant le rendez-vous, ou null pour une heure choisie librement.
  int? _delai = 30;
  TimeOfDay? _heureAlarme;
  String? _musique;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    final r = widget.rdv;
    if (r != null) {
      final debut = lireDate(r['debut'])!;
      _date = DateTime(debut.year, debut.month, debut.day);
      _heure = TimeOfDay.fromDateTime(debut);
      _type = r['type'] as String;
      _duree = (r['duree_min'] as num?)?.toInt() ?? 30;
      _note.text = r['note'] as String? ?? '';
      _commandeId = r['commande_id'] as String?;
      _commandeNumero = (r['commandes'] as Map?)?['numero'] as String?;
      final alarme = lireDate(r['alarme_a']);
      _alarme = alarme != null;
      if (alarme != null) {
        final minutes = debut.difference(alarme).inMinutes;
        if (_delais.containsKey(minutes)) {
          _delai = minutes;
        } else {
          _delai = null;
          _heureAlarme = TimeOfDay.fromDateTime(alarme);
        }
      }
      _chargerClient(r['client_id'] as String?, rdvId: r['id'] as String);
      Alarmes.sonneriePour(r['id'] as String).then((m) {
        if (mounted) setState(() => _musique = m);
      });
    } else {
      final demain = aujourdhui().add(const Duration(days: 1));
      _date = demain;
      _heure = const TimeOfDay(hour: 10, minute: 0);
      _client = widget.client;
      if (widget.commande != null) {
        _commandeId = widget.commande!['id'] as String;
        _commandeNumero = widget.commande!['numero'] as String?;
      }
    }
  }

  /// Charge le client du rendez-vous ; si son identifiant n'a pas été transmis,
  /// il est relu depuis le rendez-vous.
  Future<void> _chargerClient(String? id, {required String rdvId}) async {
    try {
      id ??= (await supa.from('rendez_vous').select('client_id').eq('id', rdvId).single())['client_id'] as String;
      final c = await supa.from('clients').select().eq('id', id).single();
      if (mounted) setState(() => _client = c);
    } catch (_) {}
  }

  DateTime get _debut => DateTime(_date.year, _date.month, _date.day, _heure.hour, _heure.minute);

  bool get _alarmesIncluses => Session.instance.offre.alarmes;

  DateTime? get _momentAlarme {
    if (!_alarme || !_alarmesIncluses) return null;
    if (_delai != null) return _debut.subtract(Duration(minutes: _delai!));
    final h = _heureAlarme ?? _heure;
    return DateTime(_date.year, _date.month, _date.day, h.hour, h.minute);
  }

  Future<void> _choisirClient() async {
    final c = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ClientsScreen(modeSelection: true)),
    );
    if (c != null) setState(() => _client = c);
  }

  Future<void> _choisirMusique() async {
    final m = await Alarmes.choisirMusique();
    if (m != null) setState(() => _musique = m);
  }

  Future<void> _enregistrer() async {
    if (_client == null) {
      snack(context, 'Choisissez un client', erreur: true);
      return;
    }
    final alarme = _momentAlarme;
    if (alarme != null && !alarme.isAfter(DateTime.now())) {
      final ok = await confirmer(context, 'Heure d\'alarme passée',
          'L\'heure de l\'alarme (${dateHeure(alarme)}) est déjà passée : elle ne sonnera pas. Enregistrer quand même ?');
      if (!ok) return;
    }
    setState(() => _occupe = true);
    try {
      final data = {
        'atelier_id': Session.instance.atelierId,
        'client_id': _client!['id'],
        'commande_id': _commandeId,
        'type': _type,
        'debut': _debut.toUtc().toIso8601String(),
        'duree_min': _duree,
        'alarme_a': alarme?.toUtc().toIso8601String(),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      };
      final Map<String, dynamic> r;
      if (widget.rdv == null) {
        r = await supa.from('rendez_vous').insert(data).select('*, clients(nom)').single();
      } else {
        r = await supa
            .from('rendez_vous')
            .update(data)
            .eq('id', widget.rdv!['id'] as String)
            .select('*, clients(nom)')
            .single();
      }
      final id = r['id'] as String;
      await Alarmes.definirSonneriePour(id, _musique);
      if (alarme != null && r['statut'] == 'prevu') {
        await Alarmes.demanderPermissions();
        await Alarmes.programmer(
          rdvId: id,
          quand: alarme,
          titre: Alarmes.titrePour(r),
          corps: Alarmes.corpsPour(r),
        );
      } else {
        await Alarmes.annuler(id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _supprimer() async {
    if (!await confirmer(context, 'Supprimer', 'Supprimer ce rendez-vous ?', ok: 'Supprimer')) return;
    try {
      final id = widget.rdv!['id'] as String;
      await supa.from('rendez_vous').delete().eq('id', id);
      await Alarmes.annuler(id);
      await Alarmes.definirSonneriePour(id, null);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final alarme = _momentAlarme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rdv == null ? 'Nouveau rendez-vous' : 'Rendez-vous'),
        actions: [
          if (widget.rdv != null && Session.instance.estGestionnaire)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _supprimer),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person),
          title: Text(_client?['nom'] as String? ?? 'Choisir un client *'),
          subtitle: _commandeNumero == null ? null : Text('Commande $_commandeNumero'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _choisirClient,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type de rendez-vous'),
          items: [for (final e in typesRdv.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _type = v ?? 'essayage'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(dateCourte(_date)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: aujourdhui().subtract(const Duration(days: 365)),
                  lastDate: aujourdhui().add(const Duration(days: 730)),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(_heure.format(context)),
              onPressed: () async {
                final h = await showTimePicker(context: context, initialTime: _heure);
                if (h != null) setState(() => _heure = h);
              },
            ),
          ),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _duree,
          decoration: const InputDecoration(labelText: 'Durée'),
          items: [
            for (final d in const [15, 30, 45, 60, 90, 120])
              DropdownMenuItem(value: d, child: Text(d < 60 ? '$d min' : '${d ~/ 60} h${d % 60 == 0 ? '' : ' ${d % 60}'}')),
          ],
          onChanged: (v) => setState(() => _duree = v ?? 30),
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'Note')),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.alarm),
                title: const Text('Alarme musicale'),
                subtitle: Text(!_alarmesIncluses
                    ? 'Disponible à partir de la formule Standard'
                    : Alarmes.supporte
                        ? 'Sonne sur ce téléphone avec la musique choisie'
                        : 'Enregistrée ici, elle sonnera sur les téléphones de l\'équipe'),
                value: _alarme && _alarmesIncluses,
                onChanged: (v) {
                  if (_alarmesIncluses) {
                    setState(() => _alarme = v);
                  } else {
                    proposerFormule(context,
                        'Les alarmes musicales des rendez-vous sont disponibles à partir de la formule Standard.');
                  }
                },
              ),
              if (_alarme && _alarmesIncluses) ...[
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in _delais.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _delai == e.key,
                      onSelected: (_) => setState(() => _delai = e.key),
                    ),
                  ChoiceChip(
                    label: Text(_delai == null && _heureAlarme != null ? 'À ${_heureAlarme!.format(context)}' : 'Heure précise…'),
                    selected: _delai == null,
                    onSelected: (_) async {
                      final h = await showTimePicker(context: context, initialTime: _heureAlarme ?? _heure);
                      if (h != null) {
                        setState(() {
                          _delai = null;
                          _heureAlarme = h;
                        });
                      }
                    },
                  ),
                ]),
                if (alarme != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('L\'alarme sonnera le ${dateHeure(alarme)}', style: t.textTheme.titleSmall),
                  ),
                if (Alarmes.supporte)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.library_music),
                    title: Text(_musique == null ? 'Sonnerie par défaut' : Alarmes.nomFichier(_musique)),
                    subtitle: const Text('Choisir une musique du téléphone'),
                    trailing: _musique == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _musique = null)),
                    onTap: _choisirMusique,
                  ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _occupe ? null : _enregistrer,
          icon: const Icon(Icons.check),
          label: const Text('Enregistrer'),
        ),
      ]),
    );
  }
}
