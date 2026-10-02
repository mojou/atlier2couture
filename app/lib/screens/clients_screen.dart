import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'client_detail_screen.dart';
import 'client_form_screen.dart';

/// Liste des clients. En mode sélection, un appui renvoie le client choisi.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, this.modeSelection = false});

  final bool modeSelection;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  late Future<List<Map<String, dynamic>>> _f = _charger();
  String _recherche = '';

  Future<List<Map<String, dynamic>>> _charger() => supa
      .from('clients')
      .select()
      .eq('atelier_id', Session.instance.atelierId)
      .order('nom');

  void _recharger() => setState(() => _f = _charger());

  Future<void> _nouveau() async {
    final c = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ClientFormScreen()),
    );
    if (c == null || !mounted) return;
    if (widget.modeSelection) {
      Navigator.pop(context, c);
    } else {
      _recharger();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.modeSelection ? 'Choisir un client' : 'Clients')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nouveau,
        icon: const Icon(Icons.person_add),
        label: const Text('Nouveau client'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom ou téléphone'),
            onChanged: (v) => setState(() => _recherche = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: AsyncVue<List<Map<String, dynamic>>>(
            future: _f,
            onReessayer: _recharger,
            builder: (context, clients) {
              final liste = clients.where((c) {
                if (_recherche.isEmpty) return true;
                return (c['nom'] as String).toLowerCase().contains(_recherche) ||
                    ((c['telephone'] as String?) ?? '').replaceAll(' ', '').contains(_recherche.replaceAll(' ', ''));
              }).toList();
              if (liste.isEmpty) {
                return EtatVide(
                  icone: Icons.people_outline,
                  message: clients.isEmpty ? 'Aucun client pour le moment.' : 'Aucun résultat.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: liste.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final c = liste[i];
                  final nom = c['nom'] as String;
                  return ListTile(
                    leading: CircleAvatar(child: Text(nom.isEmpty ? '?' : nom[0].toUpperCase())),
                    title: Text(nom),
                    subtitle: Text((c['telephone'] as String?) ?? ''),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      if (widget.modeSelection) {
                        Navigator.pop(context, c);
                        return;
                      }
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ClientDetailScreen(clientId: c['id'] as String),
                      ));
                      if (mounted) _recharger();
                    },
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
