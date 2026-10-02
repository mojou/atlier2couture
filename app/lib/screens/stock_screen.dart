import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

bool _stockBas(Map<String, dynamic> a) =>
    num0(a['seuil_alerte']) > 0 && num0(a['quantite']) <= num0(a['seuil_alerte']);

/// Stock de l'atelier. En mode sélection, renvoie l'article choisi
/// (limité éventuellement à certaines catégories).
class StockScreen extends StatefulWidget {
  const StockScreen({super.key, this.modeSelection = false, this.categories});

  final bool modeSelection;
  final Set<String>? categories;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  late Future<List<Map<String, dynamic>>> _f = _charger();
  String? _categorie;
  bool _basSeulement = false;
  String _recherche = '';

  Future<List<Map<String, dynamic>>> _charger() {
    var q = supa.from('stock_articles').select().eq('atelier_id', Session.instance.atelierId);
    if (widget.categories != null) q = q.inFilter('categorie', widget.categories!.toList());
    return q.order('categorie').order('nom');
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    if (mounted) _recharger();
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.categories ?? categoriesStock.keys.toSet();
    return Scaffold(
      appBar: AppBar(title: Text(widget.modeSelection ? 'Choisir dans le stock' : 'Stock')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ouvrir(StockArticleFormScreen(categorieInitiale: _categorie ?? cats.first)),
        icon: const Icon(Icons.add),
        label: const Text('Article'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher'),
            onChanged: (v) => setState(() => _recherche = v.trim().toLowerCase()),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            FilterChip(
              label: const Text('Stock bas'),
              avatar: const Icon(Icons.warning_amber, size: 18),
              selected: _basSeulement,
              onSelected: (v) => setState(() => _basSeulement = v),
            ),
            const SizedBox(width: 8),
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(categoriesStock[c] ?? c),
                  selected: _categorie == c,
                  onSelected: (s) => setState(() => _categorie = s ? c : null),
                ),
              ),
          ]),
        ),
        Expanded(
          child: AsyncVue<List<Map<String, dynamic>>>(
            future: _f,
            onReessayer: _recharger,
            builder: (context, articles) {
              final liste = articles.where((a) {
                if (_categorie != null && a['categorie'] != _categorie) return false;
                if (_basSeulement && !_stockBas(a)) return false;
                if (_recherche.isNotEmpty &&
                    !'${a['nom']} ${a['reference'] ?? ''} ${a['couleur'] ?? ''}'.toLowerCase().contains(_recherche)) {
                  return false;
                }
                return true;
              }).toList();
              if (liste.isEmpty) {
                return const EtatVide(icone: Icons.inventory_2_outlined, message: 'Aucun article.');
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: liste.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final a = liste[i];
                  final bas = _stockBas(a);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: bas ? Colors.red.shade100 : null,
                      child: Icon(bas ? Icons.warning_amber : Icons.inventory_2, color: bas ? Colors.red : null),
                    ),
                    title: Text(a['nom'] as String),
                    subtitle: Text([
                      categoriesStock[a['categorie']] ?? '',
                      if (a['couleur'] != null) a['couleur'] as String,
                      if (a['largeur_cm'] != null) 'laize ${nombre(num0(a['largeur_cm']))} cm',
                      'vente ${argent(num0(a['prix_vente']))}/${a['unite']}',
                    ].join(' · ')),
                    trailing: Text(
                      '${nombre(num0(a['quantite']))} ${a['unite']}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: bas ? Colors.red : null),
                    ),
                    onTap: () {
                      if (widget.modeSelection) {
                        Navigator.pop(context, a);
                      } else {
                        _ouvrir(StockArticleDetailScreen(articleId: a['id'] as String));
                      }
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

class StockArticleDetailScreen extends StatefulWidget {
  const StockArticleDetailScreen({super.key, required this.articleId});

  final String articleId;

  @override
  State<StockArticleDetailScreen> createState() => _StockArticleDetailScreenState();
}

class _StockArticleDetailScreenState extends State<StockArticleDetailScreen> {
  late Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> _f = _charger();

  Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> _charger() async {
    final a = await supa.from('stock_articles').select().eq('id', widget.articleId).single();
    final m = await supa
        .from('stock_mouvements')
        .select()
        .eq('article_id', widget.articleId)
        .order('created_at', ascending: false)
        .limit(100);
    return (a, m);
  }

  void _recharger() => setState(() => _f = _charger());

  Future<void> _mouvement(Map<String, dynamic> a, String type) async {
    final qte = TextEditingController();
    final motif = TextEditingController();
    final unite = a['unite'] as String;
    final titre = switch (type) {
      'entree' => 'Entrée en stock (achat)',
      'sortie' => 'Sortie de stock',
      _ => 'Inventaire (quantité réelle)',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titre),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (type == 'ajustement') Text('Quantité enregistrée : ${nombre(num0(a['quantite']))} $unite'),
          const SizedBox(height: 8),
          ChampNombre(
            controller: qte,
            label: type == 'ajustement' ? 'Quantité comptée' : 'Quantité',
            suffixe: unite,
            obligatoire: true,
          ),
          const SizedBox(height: 12),
          TextField(controller: motif, decoration: const InputDecoration(labelText: 'Motif / fournisseur')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Valider')),
        ],
      ),
    );
    if (ok != true) return;
    final q = lireNombre(qte.text);
    if (q == null || q < 0 || (type != 'ajustement' && q == 0)) {
      if (mounted) snack(context, 'Quantité invalide', erreur: true);
      return;
    }
    final quantite = type == 'ajustement' ? q - num0(a['quantite']) : q;
    if (quantite == 0) return;
    try {
      await supa.from('stock_mouvements').insert({
        'atelier_id': Session.instance.atelierId,
        'article_id': a['id'],
        'type': type,
        'quantite': quantite,
        'motif': motif.text.trim().isEmpty ? null : motif.text.trim(),
      });
      _recharger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _supprimer(Map<String, dynamic> a) async {
    if (!await confirmer(context, 'Supprimer', 'Supprimer « ${a['nom']} » et son historique ?', ok: 'Supprimer')) return;
    try {
      await supa.from('stock_articles').delete().eq('id', a['id'] as String);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncVue<(Map<String, dynamic>, List<Map<String, dynamic>>)>(
      future: _f,
      onReessayer: _recharger,
      pleinEcran: true,
      builder: (context, data) {
        final (a, mouvements) = data;
        final t = Theme.of(context);
        final bas = _stockBas(a);
        return Scaffold(
          appBar: AppBar(
            title: Text(a['nom'] as String),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockArticleFormScreen(article: a)));
                  _recharger();
                },
              ),
              if (Session.instance.estGestionnaire)
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _supprimer(a)),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Card(
              margin: const EdgeInsets.all(12),
              color: bas ? Colors.red.shade50 : t.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('${nombre(num0(a['quantite']))} ${a['unite']}',
                      style: t.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                  if (bas) const Text('Stock bas : pensez à réapprovisionner', style: TextStyle(color: Colors.red)),
                  Text('Seuil d\'alerte : ${nombre(num0(a['seuil_alerte']))} ${a['unite']}'),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                    onPressed: () => _mouvement(a, 'entree'), icon: const Icon(Icons.add), label: const Text('Entrée')),
                FilledButton.tonalIcon(
                    onPressed: () => _mouvement(a, 'sortie'), icon: const Icon(Icons.remove), label: const Text('Sortie')),
                OutlinedButton.icon(
                    onPressed: () => _mouvement(a, 'ajustement'),
                    icon: const Icon(Icons.fact_check),
                    label: const Text('Inventaire')),
              ]),
            ),
            Section(titre: 'Informations', children: [
              Text('Catégorie : ${categoriesStock[a['categorie']] ?? a['categorie']}'),
              if (a['reference'] != null) Text('Référence : ${a['reference']}'),
              if (a['couleur'] != null) Text('Couleur / motif : ${a['couleur']}'),
              if (a['largeur_cm'] != null) Text('Laize : ${nombre(num0(a['largeur_cm']))} cm'),
              Text('Prix d\'achat : ${argent(num0(a['prix_achat']))} / ${a['unite']}'),
              Text('Prix de vente : ${argent(num0(a['prix_vente']))} / ${a['unite']}'),
              Text('Valeur du stock : ${argent(num0(a['quantite']) * num0(a['prix_achat']))}'),
              if (a['fournisseur'] != null) Text('Fournisseur : ${a['fournisseur']}'),
            ]),
            Section(titre: 'Mouvements', children: [
              if (mouvements.isEmpty) const Text('Aucun mouvement.'),
              for (final m in mouvements)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    m['type'] == 'entree' ? Icons.arrow_downward : (m['type'] == 'sortie' ? Icons.arrow_upward : Icons.tune),
                    color: m['type'] == 'entree' ? Colors.green : (m['type'] == 'sortie' ? Colors.red : Colors.blueGrey),
                  ),
                  title: Text('${m['type'] == 'sortie' ? '-' : (num0(m['quantite']) > 0 ? '+' : '')}'
                      '${nombre(num0(m['quantite']))} ${a['unite']}'),
                  subtitle: Text('${dateHeure(lireDate(m['created_at'])!)}${m['motif'] == null ? '' : ' · ${m['motif']}'}'),
                ),
            ]),
          ]),
        );
      },
    );
  }
}

class StockArticleFormScreen extends StatefulWidget {
  const StockArticleFormScreen({super.key, this.article, this.categorieInitiale = 'tissu'});

  final Map<String, dynamic>? article;
  final String categorieInitiale;

  @override
  State<StockArticleFormScreen> createState() => _StockArticleFormScreenState();
}

class _StockArticleFormScreenState extends State<StockArticleFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _a = widget.article ?? const {};
  late String _categorie = _a['categorie'] as String? ?? widget.categorieInitiale;
  late final _nom = TextEditingController(text: _a['nom'] as String? ?? '');
  late final _reference = TextEditingController(text: _a['reference'] as String? ?? '');
  late final _couleur = TextEditingController(text: _a['couleur'] as String? ?? '');
  late final _unite = TextEditingController(text: _a['unite'] as String? ?? _uniteDefaut(_categorie));
  late final _quantite = TextEditingController();
  late final _seuil = TextEditingController(text: nombreChamp(_a['seuil_alerte'] as num?));
  late final _prixAchat = TextEditingController(text: nombreChamp(_a['prix_achat'] as num?));
  late final _prixVente = TextEditingController(text: nombreChamp(_a['prix_vente'] as num?));
  late final _largeur = TextEditingController(text: nombreChamp(_a['largeur_cm'] as num?));
  late final _fournisseur = TextEditingController(text: _a['fournisseur'] as String? ?? '');
  bool _occupe = false;

  bool get _estTissu => const {'tissu', 'doublure', 'entoilage'}.contains(_categorie);

  static String _uniteDefaut(String categorie) => unitesParCategorie[categorie] ?? Session.instance.unite;

  String? _vide(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _occupe = true);
    try {
      final data = {
        'atelier_id': Session.instance.atelierId,
        'nom': _nom.text.trim(),
        'categorie': _categorie,
        'reference': _vide(_reference),
        'couleur': _vide(_couleur),
        'unite': _unite.text.trim().isEmpty ? _uniteDefaut(_categorie) : _unite.text.trim(),
        'seuil_alerte': lireNombre(_seuil.text) ?? 0,
        'prix_achat': lireNombre(_prixAchat.text) ?? 0,
        'prix_vente': lireNombre(_prixVente.text) ?? 0,
        'largeur_cm': _estTissu ? lireNombre(_largeur.text) : null,
        'fournisseur': _vide(_fournisseur),
      };
      if (widget.article == null) {
        final a = await supa.from('stock_articles').insert(data).select().single();
        final q = lireNombre(_quantite.text) ?? 0;
        if (q > 0) {
          await supa.from('stock_mouvements').insert({
            'atelier_id': Session.instance.atelierId,
            'article_id': a['id'],
            'type': 'entree',
            'quantite': q,
            'motif': 'Stock initial',
          });
        }
      } else {
        await supa.from('stock_articles').update(data).eq('id', widget.article!['id'] as String);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devise = Session.instance.devise;
    return Scaffold(
      appBar: AppBar(title: Text(widget.article == null ? 'Nouvel article' : 'Modifier l\'article')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<String>(
            initialValue: _categorie,
            decoration: const InputDecoration(labelText: 'Catégorie'),
            items: [for (final e in categoriesStock.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() {
              _categorie = v ?? 'tissu';
              if (widget.article == null) _unite.text = _uniteDefaut(_categorie);
            }),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nom,
            decoration: const InputDecoration(labelText: 'Nom *', hintText: 'ex : Bazin riche blanc'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _reference, decoration: const InputDecoration(labelText: 'Référence'))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _couleur, decoration: const InputDecoration(labelText: 'Couleur / motif'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _unite, decoration: const InputDecoration(labelText: 'Unité'))),
            const SizedBox(width: 12),
            if (widget.article == null)
              Expanded(child: ChampNombre(controller: _quantite, label: 'Quantité en stock'))
            else
              const Spacer(),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ChampNombre(controller: _seuil, label: 'Seuil d\'alerte')),
            const SizedBox(width: 12),
            if (_estTissu)
              Expanded(child: ChampNombre(controller: _largeur, label: 'Laize (largeur)', suffixe: 'cm'))
            else
              const Spacer(),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ChampNombre(controller: _prixAchat, label: 'Prix d\'achat', suffixe: devise)),
            const SizedBox(width: 12),
            Expanded(child: ChampNombre(controller: _prixVente, label: 'Prix de vente', suffixe: devise)),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: _fournisseur, decoration: const InputDecoration(labelText: 'Fournisseur')),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _occupe ? null : _enregistrer,
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer'),
          ),
        ]),
      ),
    );
  }
}
