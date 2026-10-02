import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/contact.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../services/alarmes.dart';
import 'rdv_form_screen.dart';

/// Agenda des rendez-vous (prise de mesures, essayage, livraison…).
class RendezVousScreen extends StatefulWidget {
  const RendezVousScreen({super.key});

  @override
  State<RendezVousScreen> createState() => _RendezVousScreenState();
}

class _RendezVousScreenState extends State<RendezVousScreen> {
  bool _passes = false;
  late Future<List<Map<String, dynamic>>> _f = _charger();

  Future<List<Map<String, dynamic>>> _charger() {
    final debutJour = aujourdhui().toUtc().toIso8601String();
    final q = supa
        .from('rendez_vous')
        .select('*, clients(nom, telephone), commandes(numero)')
        .eq('atelier_id', Session.instance.atelierId);
    return _passes
        ? q.lt('debut', debutJour).order('debut', ascending: false).limit(200)
        : q.gte('debut', debutJour).order('debut').limit(300);
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    if (mounted) _recharger();
  }

  Future<void> _statut(Map<String, dynamic> r, String statut) async {
    try {
      await supa.from('rendez_vous').update({'statut': statut}).eq('id', r['id'] as String);
      if (statut != 'prevu') await Alarmes.annuler(r['id'] as String);
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  void _rappelWhatsApp(Map<String, dynamic> r) {
    final client = r['clients'] as Map? ?? const {};
    final debut = lireDate(r['debut'])!;
    ouvrirWhatsApp(
      context,
      client['telephone'] as String?,
      'Bonjour ${client['nom'] ?? ''}, nous vous rappelons votre rendez-vous '
      '(${(typesRdv[r['type']] ?? '').toLowerCase()}) le ${jourLong(debut)} à ${heure(debut)} '
      'chez ${Session.instance.atelier['nom']}. À bientôt !',
    );
  }

  String _titreJour(DateTime d) {
    final j = DateTime(d.year, d.month, d.day);
    final diff = j.difference(aujourdhui()).inDays;
    if (diff == 0) return 'Aujourd\'hui';
    if (diff == 1) return 'Demain';
    if (diff == -1) return 'Hier';
    final s = jourLong(d);
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendez-vous'),
        actions: [
          IconButton(
            tooltip: 'Resynchroniser les alarmes',
            icon: const Icon(Icons.alarm),
            onPressed: () async {
              await Alarmes.synchroniser();
              if (context.mounted) {
                snack(context, Alarmes.supporte
                    ? 'Alarmes à jour sur ce téléphone'
                    : 'Les alarmes sonnent uniquement sur l\'application mobile');
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ouvrir(const RdvFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Rendez-vous'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('À venir')),
              ButtonSegment(value: true, label: Text('Passés')),
            ],
            selected: {_passes},
            onSelectionChanged: (s) {
              _passes = s.first;
              _recharger();
            },
          ),
        ),
        Expanded(
          child: AsyncVue<List<Map<String, dynamic>>>(
            future: _f,
            onReessayer: _recharger,
            builder: (context, rdvs) {
              if (rdvs.isEmpty) {
                return const EtatVide(icone: Icons.event_available, message: 'Aucun rendez-vous.');
              }
              final enfants = <Widget>[];
              String? jourPrecedent;
              for (final r in rdvs) {
                final debut = lireDate(r['debut'])!;
                final jour = _titreJour(debut);
                if (jour != jourPrecedent) {
                  enfants.add(Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(jour, style: Theme.of(context).textTheme.titleSmall),
                  ));
                  jourPrecedent = jour;
                }
                enfants.add(_tuile(r, debut));
              }
              return ListView(padding: const EdgeInsets.only(bottom: 88), children: enfants);
            },
          ),
        ),
      ]),
    );
  }

  Widget _tuile(Map<String, dynamic> r, DateTime debut) {
    final statut = r['statut'] as String;
    final alarme = lireDate(r['alarme_a']);
    final annule = statut == 'annule';
    return ListTile(
      leading: CircleAvatar(child: Icon(iconeRdv(r['type'] as String))),
      title: Text(
        '${heure(debut)} · ${(r['clients'] as Map?)?['nom'] ?? ''}',
        style: TextStyle(decoration: annule ? TextDecoration.lineThrough : null),
      ),
      subtitle: Text([
        typesRdv[r['type']] ?? '',
        if (r['commandes'] != null) (r['commandes'] as Map)['numero'] as String? ?? '',
        if (alarme != null && statut == 'prevu') 'alarme ${heure(alarme)}',
        if (statut != 'prevu') statutsRdv[statut] ?? '',
        if (r['note'] != null) r['note'] as String,
      ].where((e) => e.isNotEmpty).join(' · ')),
      trailing: PopupMenuButton<String>(
        onSelected: (a) {
          if (a == 'whatsapp') {
            _rappelWhatsApp(r);
          } else {
            _statut(r, a);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'whatsapp', child: Text('Rappel WhatsApp au client')),
          for (final e in statutsRdv.entries)
            if (e.key != statut) PopupMenuItem(value: e.key, child: Text('Marquer : ${e.value}')),
        ],
      ),
      onTap: () => _ouvrir(RdvFormScreen(rdv: r)),
    );
  }
}
