import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/contact.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

class _Rappel {
  _Rappel(this.cle, this.nom, this.telephone, this.detail, this.message);

  final String cle;
  final String nom;
  final String? telephone;
  final String detail;
  final String message;
}

class _Donnees {
  _Donnees(this.rdvs, this.pretes, this.impayes);

  final List<_Rappel> rdvs;
  final List<_Rappel> pretes;
  final List<_Rappel> impayes;
}

/// Rappels WhatsApp groupés (formule Premium) : un message pré-rempli par
/// client, envoyé l'un après l'autre en un appui.
class RappelsScreen extends StatefulWidget {
  const RappelsScreen({super.key});

  @override
  State<RappelsScreen> createState() => _RappelsScreenState();
}

class _RappelsScreenState extends State<RappelsScreen> {
  late Future<_Donnees> _f = _charger();
  final _envoyes = <String>{};

  String get _atelier => Session.instance.atelier['nom'] as String? ?? '';

  Future<_Donnees> _charger() async {
    final id = Session.instance.atelierId;
    final demain = aujourdhui().add(const Duration(days: 1));
    final r = await Future.wait<List<Map<String, dynamic>>>([
      supa
          .from('rendez_vous')
          .select('id, type, debut, clients(nom, telephone)')
          .eq('atelier_id', id)
          .eq('statut', 'prevu')
          .gte('debut', demain.toUtc().toIso8601String())
          .lt('debut', demain.add(const Duration(days: 1)).toUtc().toIso8601String())
          .order('debut'),
      supa
          .from('commandes')
          .select('id, numero, clients(nom, telephone)')
          .eq('atelier_id', id)
          .eq('statut', 'prete')
          .order('date_livraison'),
      supa
          .from('documents')
          .select('id, numero, total, montant_paye, clients(nom, telephone)')
          .eq('atelier_id', id)
          .eq('type', 'facture')
          .inFilter('statut', ['impayee', 'partielle'])
          .order('date_emission'),
    ]);

    String nom(Map<String, dynamic> x) => (x['clients'] as Map?)?['nom'] as String? ?? '';
    String? tel(Map<String, dynamic> x) => (x['clients'] as Map?)?['telephone'] as String?;

    return _Donnees(
      [
        for (final x in r[0])
          _Rappel(
            'rdv-${x['id']}',
            nom(x),
            tel(x),
            '${typesRdv[x['type']]} demain à ${heure(lireDate(x['debut'])!)}',
            'Bonjour ${nom(x)}, nous vous rappelons votre rendez-vous '
                '(${(typesRdv[x['type']] ?? '').toLowerCase()}) demain à ${heure(lireDate(x['debut'])!)} '
                'chez $_atelier. À demain !',
          ),
      ],
      [
        for (final x in r[1])
          _Rappel(
            'cmd-${x['id']}',
            nom(x),
            tel(x),
            'Commande ${x['numero']} prête',
            'Bonjour ${nom(x)}, votre commande ${x['numero']} est prête chez $_atelier. '
                'Vous pouvez passer la récupérer. Merci !',
          ),
      ],
      [
        for (final x in r[2])
          _Rappel(
            'fac-${x['id']}',
            nom(x),
            tel(x),
            'Facture ${x['numero']} · reste ${argent(num0(x['total']) - num0(x['montant_paye']))}',
            'Bonjour ${nom(x)}, sauf erreur de notre part, il reste '
                '${argent(num0(x['total']) - num0(x['montant_paye']))} à régler sur la facture ${x['numero']} '
                'de $_atelier. Merci de votre confiance !',
          ),
      ],
    );
  }

  Future<void> _envoyer(_Rappel r) async {
    await ouvrirWhatsApp(context, r.telephone, r.message);
    if (mounted) setState(() => _envoyes.add(r.cle));
  }

  /// Ouvre le prochain message non envoyé de la liste.
  Future<void> _suivant(List<_Rappel> liste) async {
    for (final r in liste) {
      if (!_envoyes.contains(r.cle) && (r.telephone ?? '').isNotEmpty) {
        await _envoyer(r);
        return;
      }
    }
    if (mounted) snack(context, 'Tous les rappels de cette liste ont été envoyés.');
  }

  Widget _section(String titre, IconData icone, List<_Rappel> liste) {
    final restants = liste.where((r) => !_envoyes.contains(r.cle)).length;
    return Section(
      titre: '$titre (${liste.length})',
      action: liste.isEmpty
          ? null
          : FilledButton.tonalIcon(
              onPressed: restants == 0 ? null : () => _suivant(liste),
              icon: const Icon(Icons.send),
              label: Text(restants == 0 ? 'Terminé' : 'Suivant ($restants)'),
            ),
      children: [
        if (liste.isEmpty) const Text('Rien à envoyer.'),
        for (final r in liste)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_envoyes.contains(r.cle) ? Icons.check_circle : icone,
                color: _envoyes.contains(r.cle) ? Colors.green : null),
            title: Text(r.nom),
            subtitle: Text((r.telephone ?? '').isEmpty ? '${r.detail} · pas de numéro' : r.detail),
            trailing: IconButton(
              tooltip: 'Envoyer sur WhatsApp',
              icon: const Icon(Icons.chat),
              onPressed: (r.telephone ?? '').isEmpty ? null : () => _envoyer(r),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rappels WhatsApp')),
      body: AsyncVue<_Donnees>(
        future: _f,
        onReessayer: () => setState(() => _f = _charger()),
        builder: (context, d) => ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Touchez « Suivant » : WhatsApp s\'ouvre avec le message prêt. Envoyez-le, '
                'revenez ici et touchez à nouveau « Suivant » pour le client suivant.'),
          ),
          _section('Rendez-vous de demain', Icons.event, d.rdvs),
          _section('Commandes prêtes à retirer', Icons.checkroom, d.pretes),
          _section('Factures impayées', Icons.money_off, d.impayes),
        ]),
      ),
    );
  }
}
