import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../core/session.dart';
import '../core/supa.dart';
import 'abonnement_screen.dart';
import 'clients_screen.dart';
import 'commandes_screen.dart';
import 'dashboard_screen.dart';
import 'messagerie_screen.dart';
import 'plus_screen.dart';
import 'rendez_vous_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Messages non lus (badge de l'onglet Messages), tenu à jour en temps réel.
  int _nonLus = 0;
  RealtimeChannel? _canal;
  Timer? _rafraichir;

  static const _ongletMessages = 4;

  static const _destinations = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Accueil'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Commandes'),
    (Icons.people_outline, Icons.people, 'Clients'),
    (Icons.event_outlined, Icons.event, 'Agenda'),
    (Icons.forum_outlined, Icons.forum, 'Messages'),
    (Icons.menu, Icons.menu, 'Plus'),
  ];

  @override
  void initState() {
    super.initState();
    _compterNonLus();
    _canal = supa
        .channel('non-lus-${Session.instance.atelierId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'atelier_id',
            value: Session.instance.atelierId,
          ),
          callback: (_) {
            _rafraichir?.cancel();
            _rafraichir = Timer(const Duration(seconds: 1), _compterNonLus);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _rafraichir?.cancel();
    if (_canal != null) supa.removeChannel(_canal!);
    super.dispose();
  }

  Future<void> _compterNonLus() async {
    if (!Session.instance.offre.messagerie) return;
    try {
      final n = await supa.rpc('messagerie_non_lus', params: {'a': Session.instance.atelierId});
      if (mounted) setState(() => _nonLus = (n as num?)?.toInt() ?? 0);
    } catch (_) {
      // Messagerie pas encore installée : pas de badge.
    }
  }

  void _aller(int i) {
    setState(() => _index = i);
    // En quittant la messagerie, les conversations lues ne comptent plus.
    _compterNonLus();
  }

  Widget _icone(int i, IconData icone) {
    if (i != _ongletMessages || _nonLus == 0) return Icon(icone);
    return Badge(label: Text(_nonLus > 99 ? '99+' : '$_nonLus'), child: Icon(icone));
  }

  Widget _page() => switch (_index) {
        0 => DashboardScreen(onOnglet: _aller),
        1 => const CommandesScreen(),
        2 => const ClientsScreen(),
        3 => const RendezVousScreen(),
        4 => Session.instance.offre.messagerie
            ? const MessagerieScreen()
            : const EcranVerrouille(
                titre: 'Messagerie interne',
                message: 'Échangez avec votre équipe en temps réel : canal de l\'atelier, messages privés '
                    'et discussion sur chaque commande.',
                icone: Icons.forum_outlined,
              ),
        _ => const PlusScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 900;
    if (large) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _aller,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.content_cut, color: Theme.of(context).colorScheme.primary),
            ),
            destinations: [
              for (final (i, d) in _destinations.indexed)
                NavigationRailDestination(icon: _icone(i, d.$1), selectedIcon: _icone(i, d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _page()),
        ]),
      );
    }
    return Scaffold(
      body: _page(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _aller,
        // 6 onglets : seul l'onglet actif affiche son libellé, pour garder de la place.
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          for (final (i, d) in _destinations.indexed)
            NavigationDestination(icon: _icone(i, d.$1), selectedIcon: _icone(i, d.$2), label: d.$3),
        ],
      ),
    );
  }
}
