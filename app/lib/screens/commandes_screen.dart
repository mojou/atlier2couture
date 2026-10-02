import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'commande_detail_screen.dart';
import 'document_form_screen.dart';

class CommandesScreen extends StatefulWidget {
  const CommandesScreen({super.key});

  @override
  State<CommandesScreen> createState() => _CommandesScreenState();
}

class _CommandesScreenState extends State<CommandesScreen> {
  static const _filtres = {
    'production': 'En production',
    'prete': 'Prêtes',
    'livree': 'Livrées',
    'toutes': 'Toutes',
  };

  String _filtre = 'production';
  String _recherche = '';
  late Future<List<Map<String, dynamic>>> _f = _charger();

  Future<List<Map<String, dynamic>>> _charger() {
    var q = supa
        .from('commandes')
        .select('id, numero, statut, priorite, date_livraison, total, articles, clients(nom, telephone)')
        .eq('atelier_id', Session.instance.atelierId);
    q = switch (_filtre) {
      'production' => q.inFilter('statut', ['nouvelle', 'decoupe', 'couture', 'essayage', 'finitions']),
      'prete' => q.eq('statut', 'prete'),
      'livree' => q.eq('statut', 'livree'),
      _ => q,
    };
    if (_filtre == 'livree' || _filtre == 'toutes') {
      return q.order('created_at', ascending: false).limit(300);
    }
    return q.order('date_livraison', ascending: true, nullsFirst: false);
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    if (mounted) _recharger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commandes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ouvrir(const DocumentFormScreen(mode: 'commande')),
        icon: const Icon(Icons.add),
        label: const Text('Commande'),
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            for (final e in _filtres.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _filtre == e.key,
                  onSelected: (_) {
                    _filtre = e.key;
                    _recharger();
                  },
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Client ou numéro'),
            onChanged: (v) => setState(() => _recherche = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: AsyncVue<List<Map<String, dynamic>>>(
            future: _f,
            onReessayer: _recharger,
            builder: (context, rows) {
              final liste = rows.where((c) {
                if (_recherche.isEmpty) return true;
                final nom = ((c['clients'] as Map?)?['nom'] as String? ?? '').toLowerCase();
                return nom.contains(_recherche) || (c['numero'] as String? ?? '').toLowerCase().contains(_recherche);
              }).toList();
              if (liste.isEmpty) {
                return const EtatVide(icone: Icons.receipt_long_outlined, message: 'Aucune commande.');
              }
              return RefreshIndicator(
                onRefresh: () async => _recharger(),
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: liste.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _TuileCommande(
                    c: liste[i],
                    onTap: () => _ouvrir(CommandeDetailScreen(commandeId: liste[i]['id'] as String)),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _TuileCommande extends StatelessWidget {
  const _TuileCommande({required this.c, required this.onTap});

  final Map<String, dynamic> c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statut = c['statut'] as String;
    final livraison = lireDate(c['date_livraison']);
    final retard = livraison != null &&
        livraison.isBefore(aujourdhui()) &&
        !['prete', 'livree', 'annulee'].contains(statut);
    final articles = (c['articles'] as List? ?? const [])
        .map((a) => '${(a as Map)['designation']} ×${a['quantite']}')
        .join(', ');
    return ListTile(
      onTap: onTap,
      leading: c['priorite'] == 'urgente'
          ? const CircleAvatar(backgroundColor: Colors.red, foregroundColor: Colors.white, child: Icon(Icons.bolt))
          : const CircleAvatar(child: Icon(Icons.checkroom)),
      title: Text('${(c['clients'] as Map?)?['nom'] ?? ''} · ${c['numero'] ?? ''}'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (articles.isNotEmpty) Text(articles, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          retard ? 'EN RETARD · livraison ${dateCourte(livraison)}' : 'Livraison ${dateCourte(livraison)}',
          style: TextStyle(color: retard ? Colors.red : null, fontWeight: retard ? FontWeight.bold : null),
        ),
      ]),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Pastille(libellesStatut[statut] ?? statut, couleurStatut(statut)),
        const SizedBox(height: 4),
        Text(argent(num0(c['total'])), style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
