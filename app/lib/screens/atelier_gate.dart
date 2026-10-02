import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/support.dart';
import '../core/widgets.dart';
import '../services/alarmes.dart';
import 'admin_screen.dart';
import 'atelier_form_screen.dart';
import 'home_shell.dart';

const _cleAtelierCourant = 'atelier_courant';

const statutsAtelier = {
  'essai': 'Essai 48 h',
  'en_attente': 'En attente',
  'actif': 'Actif',
  'suspendu': 'Suspendu',
};

/// Choisit l'atelier (tenant) de travail : création du premier atelier,
/// sélection automatique du dernier utilisé, ou liste si plusieurs.
/// Un atelier en essai s'ouvre jusqu'à la fin de l'essai ; un atelier dont
/// l'essai a expiré, en attente ou suspendu n'ouvre pas l'application.
class AtelierGate extends StatefulWidget {
  const AtelierGate({super.key});

  @override
  State<AtelierGate> createState() => _AtelierGateState();
}

class _AtelierGateState extends State<AtelierGate> {
  List<Map<String, dynamic>>? _membres;
  Object? _erreur;

  /// Bascule sur l'écran de blocage à la fin de l'essai, si l'app est ouverte.
  Timer? _finEssai;

  @override
  void dispose() {
    _finEssai?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Nouvel utilisateur connecté : on oublie l'atelier de la session précédente.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Session.instance.aAtelier) Session.instance.vider();
      _charger();
    });
  }

  Future<void> _charger({String? choisir}) async {
    setState(() => _erreur = null);
    try {
      Session.instance.superAdmin = await _estSuperAdmin();
      final rows = await supa
          .from('membres')
          .select('role, ateliers(*)')
          .eq('user_id', utilisateurId!)
          .order('created_at');
      _membres = rows.where((r) => r['ateliers'] != null).toList();
      final prefs = await SharedPreferences.getInstance();
      final cible = choisir ?? prefs.getString(_cleAtelierCourant);
      Map<String, dynamic>? m;
      for (final r in _membres!) {
        if ((r['ateliers'] as Map)['id'] == cible) m = r;
      }
      if (m == null && _membres!.length == 1) m = _membres!.first;
      if (m != null) {
        await _selectionner(m);
      } else if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  Future<bool> _estSuperAdmin() async {
    try {
      return await supa.rpc('est_super_admin') == true;
    } catch (_) {
      return false; // fonction absente : espace d'administration pas encore installé
    }
  }

  Future<void> _selectionner(Map<String, dynamic> membre) async {
    final atelier = Map<String, dynamic>.from(membre['ateliers'] as Map);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cleAtelierCourant, atelier['id'] as String);
    Session.instance.definir(atelier, membre['role'] as String);
    _finEssai?.cancel();
    final fin = Session.instance.essaiFin;
    if (Session.instance.enEssai && fin != null) {
      _finEssai = Timer(
          fin.difference(DateTime.now()) + const Duration(seconds: 1), () {
        if (mounted) setState(() {});
      });
    }
    if (Session.instance.accessible) Alarmes.synchroniser();
  }

  Future<void> _nouvelAtelier() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AtelierFormScreen()),
    );
    if (id != null) await _charger(choisir: id);
  }

  void _administration() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const AdminScreen()));

  List<Widget> _actionsCommunes() => [
        if (Session.instance.superAdmin)
          IconButton(
            tooltip: 'Administration de la plateforme',
            icon: const Icon(Icons.admin_panel_settings),
            onPressed: _administration,
          ),
        IconButton(
          tooltip: 'Se déconnecter',
          icon: const Icon(Icons.logout),
          onPressed: () => supa.auth.signOut(),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) {
        final s = Session.instance;
        if (_membres != null && s.aAtelier) {
          if (s.accessible) return const HomeShell();
          return _AtelierBloque(
            actions: _actionsCommunes(),
            plusieurs: _membres!.length > 1,
            onActualiser: () => _charger(choisir: s.atelierId),
            onChanger: s.vider,
          );
        }
        if (_erreur != null) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(messageErreur(_erreur!)),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _charger, child: const Text('Réessayer')),
                TextButton(
                    onPressed: () => supa.auth.signOut(),
                    child: const Text('Se déconnecter')),
              ]),
            ),
          );
        }
        if (_membres == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (_membres!.isEmpty) {
          return AtelierFormScreen(
            premier: true,
            onCree: (id) => _charger(choisir: id),
            onAdministration: s.superAdmin ? _administration : null,
          );
        }
        return Scaffold(
          appBar: AppBar(
              title: const Text('Choisir un atelier'),
              actions: _actionsCommunes()),
          body: ListView(children: [
            for (final m in _membres!)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.store)),
                title: Text((m['ateliers'] as Map)['nom'] as String),
                subtitle: Text([
                  roles[m['role']] ?? m['role'] as String,
                  if ((m['ateliers'] as Map)['statut'] != null &&
                      (m['ateliers'] as Map)['statut'] != 'actif')
                    statutsAtelier[(m['ateliers'] as Map)['statut']] ?? '',
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _selectionner(m),
              ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.add)),
              title: const Text('Créer un nouvel atelier'),
              onTap: _nouvelAtelier,
            ),
          ]),
        );
      },
    );
  }
}

/// Écran affiché quand l'essai a expiré, ou que l'atelier est en attente ou suspendu.
class _AtelierBloque extends StatelessWidget {
  const _AtelierBloque({
    required this.actions,
    required this.plusieurs,
    required this.onActualiser,
    required this.onChanger,
  });

  final List<Widget> actions;
  final bool plusieurs;
  final VoidCallback onActualiser;
  final VoidCallback onChanger;

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    final attente = s.statut != 'suspendu';
    final motif = (s.atelier['motif_statut'] as String?)?.trim();
    final depuis = lireDate(s.atelier['statut_change_le']);
    final t = Theme.of(context);
    final (titre, message) = switch (s.statut) {
      'essai' => (
          'Période d\'essai terminée',
          'Les 48 heures d\'essai de votre atelier se sont terminées le '
              '${s.essaiFin == null ? '' : dateHeure(s.essaiFin!)}. Vos données sont conservées : '
              'contactez l\'administrateur de la plateforme pour faire activer votre atelier.',
        ),
      'suspendu' => (
          'Atelier suspendu',
          'L\'accès à cet atelier a été suspendu par l\'administrateur de la plateforme'
              '${depuis == null ? '' : ' le ${dateCourte(depuis)}'}. Contactez-le pour le réactiver.',
        ),
      _ => (
          'Atelier en attente d\'activation',
          'Votre atelier sera utilisable dès que l\'administrateur de la plateforme l\'aura activé.',
        ),
    };
    return Scaffold(
      appBar: AppBar(
          title: Text(s.atelier['nom'] as String? ?? ''), actions: actions),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(attente ? Icons.hourglass_top : Icons.block,
                  size: 72, color: attente ? Colors.orange : Colors.red),
              const SizedBox(height: 16),
              Text(titre,
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (motif != null && motif.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Message de l\'administrateur : $motif',
                        textAlign: TextAlign.center),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              BlocSupport(sujet: 'Mon atelier « ${s.atelier['nom'] ?? ''} » est bloqué.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onActualiser,
                icon: const Icon(Icons.refresh),
                label: const Text('Vérifier à nouveau'),
              ),
              if (plusieurs)
                TextButton.icon(
                  onPressed: onChanger,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Changer d\'atelier'),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
