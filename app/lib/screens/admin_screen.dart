import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/formules.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// États affichés : le statut en base, avec l'essai séparé selon qu'il court encore ou non.
const _etats = {
  'essai': 'En essai',
  'essai_expire': 'Essai expiré',
  'actif': 'Actif',
  'suspendu': 'Suspendu',
  'en_attente': 'En attente',
};

const _statuts = {
  'essai': 'essai',
  'en_attente': 'en attente',
  'actif': 'activé',
  'suspendu': 'suspendu'
};

String _etat(Map<String, dynamic> a) {
  final statut = a['statut'] as String;
  if (statut != 'essai') return statut;
  final fin = lireDate(a['essai_fin']);
  return fin != null && fin.isAfter(DateTime.now()) ? 'essai' : 'essai_expire';
}

Color _couleurEtat(String e) => switch (e) {
      'actif' => Colors.green,
      'essai' => Colors.blue,
      'suspendu' => Colors.red,
      _ => Colors.orange,
    };

String _duree(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} j ${d.inHours % 24} h';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} min';
}

/// Administration de la plateforme (super administrateur) : ateliers,
/// comptes utilisateurs et statistiques globales.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administration'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.store), text: 'Ateliers'),
            Tab(icon: Icon(Icons.people), text: 'Comptes'),
            Tab(icon: Icon(Icons.insights), text: 'Statistiques'),
          ]),
        ),
        body: const TabBarView(
            children: [_Ateliers(), _Comptes(), _Statistiques()]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ateliers
// ---------------------------------------------------------------------------

class _Ateliers extends StatefulWidget {
  const _Ateliers();

  @override
  State<_Ateliers> createState() => _AteliersState();
}

class _AteliersState extends State<_Ateliers> {
  late Future<List<Map<String, dynamic>>> _f = _charger();
  String? _filtre;
  String _recherche = '';

  Future<List<Map<String, dynamic>>> _charger() async {
    final r = await supa.rpc('admin_liste_ateliers');
    return [for (final e in r as List) Map<String, dynamic>.from(e as Map)];
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _statut(Map<String, dynamic> a, String statut) async {
    String? motif;
    if (statut == 'suspendu') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Suspendre « ${a['nom']} »'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'L\'atelier et ses employés n\'auront plus accès à l\'application. '
                'Aucune donnée n\'est supprimée.'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Message affiché à l\'atelier (facultatif)'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Suspendre'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      motif = c.text;
    }
    try {
      await supa.rpc('admin_changer_statut',
          params: {'a': a['id'], 's': statut, 'motif': motif});
      if (mounted) {
        snack(context, '« ${a['nom']} » : ${_statuts[statut]!.toLowerCase()}');
      }
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  /// Offrir ou modifier la formule à la main (geste commercial, paiement hors ligne…).
  Future<void> _formule(Map<String, dynamic> a) async {
    var f = (a['formule'] as String?) ?? 'gratuit';
    var mois = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: Text('Formule de « ${a['nom']} »'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in formules.values)
                ChoiceChip(
                  label: Text(e.prixMois == 0 ? e.nom : '${e.nom} (${e.prixMois} / mois)'),
                  selected: f == e.code,
                  onSelected: (_) => setState(() => f = e.code),
                ),
            ]),
            if (f != 'gratuit') ...[
              const SizedBox(height: 8),
              const Text('Durée offerte (ajoutée si la même formule est déjà en cours)'),
              Wrap(spacing: 6, children: [
                for (final m in const [1, 3, 6, 12])
                  ChoiceChip(label: Text('$m mois'), selected: mois == m, onSelected: (_) => setState(() => mois = m)),
              ]),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Appliquer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await supa.rpc('admin_definir_formule', params: {'a': a['id'], 'f': f, 'mois': f == 'gratuit' ? 0 : mois});
      if (mounted) snack(context, '« ${a['nom']} » : formule ${formules[f]!.nom}');
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _prolonger(Map<String, dynamic> a) async {
    try {
      await supa
          .rpc('admin_prolonger_essai', params: {'a': a['id'], 'heures': 48});
      if (mounted) snack(context, '« ${a['nom']} » : essai prolongé de 48 h');
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _supprimer(Map<String, dynamic> a) async {
    final nom = a['nom'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => _ConfirmationSaisie(
        titre: 'Supprimer « $nom »',
        message:
            'Toutes les données de cet atelier seront définitivement effacées : clients, mesures, '
            'commandes, factures, paiements, stock, rendez-vous. Les comptes des employés sont conservés.\n\n'
            'Tapez le nom de l\'atelier pour confirmer :',
        attendu: nom,
      ),
    );
    if (ok != true) return;
    try {
      await _supprimerLogo(a['id'] as String);
      await supa.rpc('admin_supprimer_atelier', params: {'a': a['id']});
      if (mounted) snack(context, '« $nom » a été supprimé');
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _supprimerLogo(String atelierId) async {
    try {
      final fichiers = await supa.storage.from('logos').list(path: atelierId);
      if (fichiers.isNotEmpty) {
        await supa.storage
            .from('logos')
            .remove([for (final f in fichiers) '$atelierId/${f.name}']);
      }
    } catch (_) {
      // Le logo orphelin n'empêche pas la suppression de l'atelier.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncVue<List<Map<String, dynamic>>>(
      future: _f,
      onReessayer: _recharger,
      builder: (context, ateliers) {
        int nb(String e) => ateliers.where((a) => _etat(a) == e).length;
        final liste = ateliers.where((a) {
          if (_filtre != null && _etat(a) != _filtre) return false;
          if (_recherche.isEmpty) return true;
          return '${a['nom']} ${a['proprietaire_email'] ?? ''} ${a['proprietaire_nom'] ?? ''} ${a['ville'] ?? ''}'
              .toLowerCase()
              .contains(_recherche);
        }).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Atelier, e-mail, ville…'),
              onChanged: (v) =>
                  setState(() => _recherche = v.trim().toLowerCase()),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              ChoiceChip(
                label: Text('Tous (${ateliers.length})'),
                selected: _filtre == null,
                onSelected: (_) => setState(() => _filtre = null),
              ),
              for (final e in _etats.entries)
                if (e.key != 'en_attente' || nb(e.key) > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text('${e.value} (${nb(e.key)})'),
                      selected: _filtre == e.key,
                      onSelected: (_) => setState(() => _filtre = e.key),
                    ),
                  ),
            ]),
          ),
          Expanded(
            child: liste.isEmpty
                ? const EtatVide(
                    icone: Icons.store_outlined, message: 'Aucun atelier.')
                : RefreshIndicator(
                    onRefresh: () async => _recharger(),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: liste.length,
                      itemBuilder: (context, i) => _carteAtelier(liste[i]),
                    ),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _carteAtelier(Map<String, dynamic> a) {
    final statut = a['statut'] as String;
    final etat = _etat(a);
    final finEssai = lireDate(a['essai_fin']);
    final t = Theme.of(context);
    final lieu = [a['ville'], a['pays']]
        .where((e) => e != null && '$e'.isNotEmpty)
        .join(', ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundImage: a['logo_url'] != null
                  ? NetworkImage(a['logo_url'] as String)
                  : null,
              child: a['logo_url'] == null ? const Icon(Icons.store) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a['nom'] as String, style: t.textTheme.titleMedium),
                    Text(
                        [
                          if (a['proprietaire_nom'] != null)
                            a['proprietaire_nom'],
                          if (a['proprietaire_email'] != null)
                            a['proprietaire_email'],
                        ].join(' · '),
                        style: t.textTheme.bodySmall),
                  ]),
            ),
            Pastille(_etats[etat] ?? etat, _couleurEtat(etat)),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Formule ${formules[a['formule']]?.nom ?? 'Gratuit'}'
              '${a['formule'] != 'gratuit' && a['formule_fin'] != null ? ' jusqu\'au ${dateCourte(lireDate(a['formule_fin']))}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (statut == 'essai' && finEssai != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                etat == 'essai'
                    ? 'Essai : se termine dans ${_duree(finEssai.difference(DateTime.now()))} (${dateHeure(finEssai)})'
                    : 'Essai terminé le ${dateHeure(finEssai)} : l\'atelier est bloqué',
                style: TextStyle(
                    color: _couleurEtat(etat), fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 8),
          Text([
            if (lieu.isNotEmpty) lieu,
            if (a['telephone'] != null) 'Tél ${a['telephone']}',
            'Inscrit le ${dateCourte(lireDate(a['created_at']))}',
          ].join(' · ')),
          Text(
              '${a['nb_membres']} membre(s) · ${a['nb_clients']} client(s) · ${a['nb_commandes']} commande(s)'
              ' · dernière activité ${dateCourte(lireDate(a['derniere_activite']))}',
              style: t.textTheme.bodySmall),
          if (a['motif_statut'] != null)
            Text('Message : ${a['motif_statut']}',
                style: t.textTheme.bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (statut != 'actif')
              FilledButton.icon(
                onPressed: () => _statut(a, 'actif'),
                icon: const Icon(Icons.check_circle),
                label: const Text('Activer'),
              ),
            OutlinedButton.icon(
              onPressed: () => _formule(a),
              icon: const Icon(Icons.workspace_premium),
              label: const Text('Formule'),
            ),
            if (statut == 'essai')
              OutlinedButton.icon(
                onPressed: () => _prolonger(a),
                icon: const Icon(Icons.more_time),
                label: Text(etat == 'essai'
                    ? 'Prolonger de 48 h'
                    : 'Nouvel essai de 48 h'),
              ),
            if (statut != 'suspendu')
              OutlinedButton.icon(
                onPressed: () => _statut(a, 'suspendu'),
                icon: const Icon(Icons.block),
                label: const Text('Suspendre'),
              ),
            TextButton.icon(
              onPressed: () => _supprimer(a),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Supprimer'),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comptes utilisateurs
// ---------------------------------------------------------------------------

class _Comptes extends StatefulWidget {
  const _Comptes();

  @override
  State<_Comptes> createState() => _ComptesState();
}

class _ComptesState extends State<_Comptes> {
  late Future<List<Map<String, dynamic>>> _f = _charger();
  String _recherche = '';

  Future<List<Map<String, dynamic>>> _charger() async {
    final r = await supa.rpc('admin_liste_utilisateurs');
    return [for (final e in r as List) Map<String, dynamic>.from(e as Map)];
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _supprimer(Map<String, dynamic> u) async {
    final email = u['email'] as String;
    var avecAteliers = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: const Text('Supprimer le compte'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Le compte $email sera définitivement supprimé : la personne ne pourra plus se connecter.'),
                if (u['ateliers'] != null) ...[
                  const SizedBox(height: 12),
                  Text('Ateliers : ${u['ateliers']}'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: avecAteliers,
                    onChanged: (v) => setState(() => avecAteliers = v ?? false),
                    title: const Text(
                        'Supprimer aussi les ateliers dont il est le seul propriétaire, avec toutes leurs données'),
                  ),
                ],
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await supa.rpc('admin_supprimer_utilisateur',
          params: {'u': u['id'], 'avec_ateliers': avecAteliers});
      if (mounted) snack(context, 'Compte $email supprimé');
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _superAdmin(Map<String, dynamic> u, bool actif) async {
    final ok = await confirmer(
      context,
      actif ? 'Nommer super administrateur' : 'Retirer les droits',
      actif
          ? '${u['email']} pourra activer, suspendre et supprimer tous les ateliers et tous les comptes.'
          : '${u['email']} n\'aura plus accès à l\'administration.',
    );
    if (!ok) return;
    try {
      await supa.rpc('admin_definir_super_admin',
          params: {'u': u['id'], 'actif': actif});
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncVue<List<Map<String, dynamic>>>(
      future: _f,
      onReessayer: _recharger,
      builder: (context, comptes) {
        final liste = comptes
            .where((u) =>
                _recherche.isEmpty ||
                '${u['email']} ${u['nom']} ${u['ateliers'] ?? ''}'
                    .toLowerCase()
                    .contains(_recherche))
            .toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: '${comptes.length} comptes'),
              onChanged: (v) =>
                  setState(() => _recherche = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: liste.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final u = liste[i];
                final moi = u['id'] == utilisateurId;
                final admin = u['super_admin'] == true;
                final nom = (u['nom'] as String?) ?? '';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: admin ? Colors.deepPurple : null,
                    foregroundColor: admin ? Colors.white : null,
                    child:
                        Icon(admin ? Icons.admin_panel_settings : Icons.person),
                  ),
                  title: Text(
                      '${nom.isEmpty ? u['email'] : nom}${moi ? ' (vous)' : ''}'),
                  subtitle: Text([
                    if (nom.isNotEmpty) u['email'] as String,
                    u['ateliers'] as String? ?? 'Aucun atelier',
                    'inscrit le ${dateCourte(lireDate(u['created_at']))}',
                    'connexion ${u['derniere_connexion'] == null ? 'jamais' : dateCourte(lireDate(u['derniere_connexion']))}',
                  ].join(' · ')),
                  isThreeLine: true,
                  trailing: moi
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'supprimer') {
                              _supprimer(u);
                            } else {
                              _superAdmin(u, v == 'admin');
                            }
                          },
                          itemBuilder: (_) => [
                            if (!admin)
                              const PopupMenuItem(
                                  value: 'admin',
                                  child: Text('Nommer super administrateur')),
                            if (admin)
                              const PopupMenuItem(
                                  value: 'retirer',
                                  child: Text(
                                      'Retirer les droits d\'administration')),
                            if (!admin)
                              const PopupMenuItem(
                                value: 'supprimer',
                                child: Text('Supprimer le compte',
                                    style: TextStyle(color: Colors.red)),
                              ),
                          ],
                        ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Statistiques
// ---------------------------------------------------------------------------

class _Statistiques extends StatefulWidget {
  const _Statistiques();

  @override
  State<_Statistiques> createState() => _StatistiquesState();
}

class _StatistiquesState extends State<_Statistiques> {
  late Future<Map<String, dynamic>> _f = _charger();

  Future<Map<String, dynamic>> _charger() async =>
      Map<String, dynamic>.from(await supa.rpc('admin_statistiques') as Map);

  @override
  Widget build(BuildContext context) {
    return AsyncVue<Map<String, dynamic>>(
      future: _f,
      onReessayer: () => setState(() => _f = _charger()),
      builder: (context, s) {
        final tuiles = [
          ('Ateliers', s['ateliers'], Icons.store, Colors.indigo),
          ('Actifs', s['actifs'], Icons.check_circle, Colors.green),
          ('Formule Gratuit', s['gratuits'], Icons.money_off, Colors.grey),
          ('Formule Standard', s['standard'], Icons.workspace_premium, Colors.blue),
          ('Formule Premium', s['premium'], Icons.diamond, Colors.amber),
          ('Revenus ce mois (FCFA)', nombre(num0(s['revenus_mois'])), Icons.payments, Colors.teal),
          ('Revenus total (FCFA)', nombre(num0(s['revenus_total'])), Icons.savings, Colors.green),
          ('Suspendus', s['suspendus'], Icons.block, Colors.red),
          (
            'Nouveaux ateliers (30 j)',
            s['ateliers_30j'],
            Icons.fiber_new,
            Colors.teal
          ),
          ('Comptes', s['utilisateurs'], Icons.people, Colors.blueGrey),
          ('Connectés (7 j)', s['connexions_7j'], Icons.login, Colors.cyan),
          ('Clients', s['clients'], Icons.person, Colors.brown),
          ('Commandes', s['commandes'], Icons.receipt_long, Colors.purple),
          (
            'Commandes (30 j)',
            s['commandes_30j'],
            Icons.trending_up,
            Colors.deepPurple
          ),
          ('Factures', s['factures'], Icons.receipt, Colors.pink),
        ];
        return RefreshIndicator(
          onRefresh: () async => setState(() => _f = _charger()),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (titre, valeur, icone, couleur) in tuiles)
                SizedBox(
                  width: 170,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icone, color: couleur),
                            const SizedBox(height: 6),
                            Text('${valeur ?? 0}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            Text(titre,
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                    ),
                  ),
                ),
            ]),
          ]),
        );
      },
    );
  }
}

/// Confirmation d'une action grave : l'utilisateur doit retaper un texte.
class _ConfirmationSaisie extends StatefulWidget {
  const _ConfirmationSaisie(
      {required this.titre, required this.message, required this.attendu});

  final String titre;
  final String message;
  final String attendu;

  @override
  State<_ConfirmationSaisie> createState() => _ConfirmationSaisieState();
}

class _ConfirmationSaisieState extends State<_ConfirmationSaisie> {
  final _c = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final ok =
        _c.text.trim().toLowerCase() == widget.attendu.trim().toLowerCase();
    return AlertDialog(
      title: Text(widget.titre),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              autofocus: true,
              decoration: InputDecoration(hintText: widget.attendu),
              onChanged: (_) => setState(() {}),
            ),
          ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: const Text('Supprimer définitivement'),
        ),
      ],
    );
  }
}
