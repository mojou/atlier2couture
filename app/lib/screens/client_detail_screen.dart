import 'package:flutter/material.dart';

import '../calcul/mesures.dart';
import '../core/constantes.dart';
import '../core/contact.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'calculateur_screen.dart';
import 'client_form_screen.dart';
import 'commande_detail_screen.dart';
import 'document_form_screen.dart';
import 'mesures_form_screen.dart';
import 'rdv_form_screen.dart';

class _Vue {
  _Vue(this.client, this.mesures, this.commandes);

  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> mesures;
  final List<Map<String, dynamic>> commandes;
}

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  late Future<_Vue> _f = _charger();

  Future<_Vue> _charger() async {
    final client = await supa.from('clients').select().eq('id', widget.clientId).single();
    final r = await Future.wait<List<Map<String, dynamic>>>([
      supa.from('mesures').select().eq('client_id', widget.clientId).order('prise_le', ascending: false),
      supa
          .from('commandes')
          .select('id, numero, statut, date_livraison, total')
          .eq('client_id', widget.clientId)
          .order('created_at', ascending: false),
    ]);
    return _Vue(client, r[0], r[1]);
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    if (mounted) _recharger();
  }

  Future<void> _supprimer(Map<String, dynamic> client) async {
    final ok = await confirmer(context, 'Supprimer le client',
        'Supprimer ${client['nom']} et ses mesures ? Impossible s\'il a des commandes ou factures.',
        ok: 'Supprimer');
    if (!ok) return;
    try {
      await supa.from('clients').delete().eq('id', client['id'] as String);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncVue<_Vue>(
      future: _f,
      onReessayer: _recharger,
      pleinEcran: true,
      builder: (context, v) {
        final c = v.client;
        final nom = c['nom'] as String;
        final derniere = v.mesures.isEmpty ? null : Mesures.depuisJson(v.mesures.first['valeurs'] as Map<String, dynamic>?);
        return Scaffold(
          appBar: AppBar(
            title: Text(nom),
            actions: [
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit),
                onPressed: () => _ouvrir(ClientFormScreen(client: c)),
              ),
              if (Session.instance.estGestionnaire)
                IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: () => _supprimer(c)),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Section(titre: 'Coordonnées', children: [
              if (c['telephone'] != null) Text('Tél : ${c['telephone']}'),
              if (c['email'] != null) Text(c['email'] as String),
              if (c['adresse'] != null) Text(c['adresse'] as String),
              if (c['notes'] != null) ...[const SizedBox(height: 6), Text(c['notes'] as String)],
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => appeler(context, c['telephone'] as String?),
                  icon: const Icon(Icons.call),
                  label: const Text('Appeler'),
                ),
                OutlinedButton.icon(
                  onPressed: () => ouvrirWhatsApp(context, c['telephone'] as String?, 'Bonjour $nom, '),
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _ouvrir(RdvFormScreen(client: c)),
                  icon: const Icon(Icons.event),
                  label: const Text('Rendez-vous'),
                ),
              ]),
            ]),
            Section(
              titre: 'Mesures (cm)',
              action: TextButton.icon(
                onPressed: () => _ouvrir(MesuresFormScreen(
                  clientId: widget.clientId,
                  nomClient: nom,
                  initiales: derniere?.valeurs,
                )),
                icon: const Icon(Icons.add),
                label: Text(derniere == null ? 'Prendre les mesures' : 'Nouvelles mesures'),
              ),
              children: [
                if (derniere == null)
                  const Text('Aucune mesure enregistrée.')
                else ...[
                  Text('Prises le ${dateCourte(lireDate(v.mesures.first['prise_le']))}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final d in mesuresDefs)
                      if (derniere.a(d.cle)) Chip(label: Text('${d.libelle} : ${nombre(derniere[d.cle])}')),
                  ]),
                  if (v.mesures.first['note'] != null) Text(v.mesures.first['note'] as String),
                  if (v.mesures.length > 1)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('Historique (${v.mesures.length - 1} prise(s) précédente(s))'),
                      children: [
                        for (final m in v.mesures.skip(1))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(dateCourte(lireDate(m['prise_le']))),
                            subtitle: Text([
                              for (final e in Mesures.depuisJson(m['valeurs'] as Map<String, dynamic>?).valeurs.entries)
                                '${libelleMesure(e.key)} ${nombre(e.value)}'
                            ].join(' · ')),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _ouvrir(CalculateurScreen(mesuresInitiales: derniere.valeurs, nomClient: nom)),
                    icon: const Icon(Icons.straighten),
                    label: const Text('Calculer un métrage avec ces mesures'),
                  ),
                ],
              ],
            ),
            Section(
              titre: 'Commandes',
              action: TextButton.icon(
                onPressed: () => _ouvrir(DocumentFormScreen(mode: 'commande', client: c)),
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle'),
              ),
              children: [
                if (v.commandes.isEmpty) const Text('Aucune commande.'),
                for (final cmd in v.commandes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(cmd['numero'] as String? ?? ''),
                    subtitle: Text('Livraison : ${dateCourte(lireDate(cmd['date_livraison']))} · ${argent(num0(cmd['total']))}'),
                    trailing: Pastille(libellesStatut[cmd['statut']] ?? '', couleurStatut(cmd['statut'] as String)),
                    onTap: () => _ouvrir(CommandeDetailScreen(commandeId: cmd['id'] as String)),
                  ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => _ouvrir(DocumentFormScreen(mode: 'devis', client: c)),
                  icon: const Icon(Icons.request_quote_outlined),
                  label: const Text('Faire un devis'),
                ),
              ],
            ),
          ]),
        );
      },
    );
  }
}
