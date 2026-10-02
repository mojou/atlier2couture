import 'package:flutter/material.dart';

import '../calcul/devis.dart';
import '../calcul/mesures.dart';
import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../models/article_commande.dart';
import 'article_form_screen.dart';
import 'clients_screen.dart';
import 'commande_detail_screen.dart';
import 'document_detail_screen.dart';
import 'stock_screen.dart';

/// Nouvelle commande (crée aussi sa facture) ou devis, avec calcul automatique
/// des montants : façon + tissu + fournitures + options − remise + TVA.
///
/// [devis] : devis existant à modifier (mode 'devis') ou à transformer en
/// commande (mode 'commande').
class DocumentFormScreen extends StatefulWidget {
  const DocumentFormScreen({super.key, required this.mode, this.client, this.devis});

  final String mode;
  final Map<String, dynamic>? client;
  final Map<String, dynamic>? devis;

  @override
  State<DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends State<DocumentFormScreen> {
  Map<String, dynamic>? _client;
  Map<String, double>? _mesuresClient;
  final _articles = <ArticleCommande>[];
  final _extras = <LigneDoc>[];
  final _remise = TextEditingController(text: '0');
  late final _tva = TextEditingController(text: nombreChamp(Session.instance.tauxTva));
  late final _acomptePct = TextEditingController(text: nombreChamp(Session.instance.acomptePct));
  final _acompteRecu = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _livraison = aujourdhui().add(const Duration(days: 7));
  String _priorite = 'normale';
  String _modePaiement = 'especes';
  bool _occupe = false;
  bool _acompteModifie = false;

  bool get _commande => widget.mode == 'commande';
  String get _unite => Session.instance.unite;
  int get _dec => Session.instance.decimales;

  @override
  void initState() {
    super.initState();
    final d = widget.devis;
    if (d != null) {
      final meta = Map<String, dynamic>.from((d['meta'] as Map?) ?? const {});
      for (final a in (meta['articles'] as List? ?? const [])) {
        _articles.add(ArticleCommande.depuisJson(Map<String, dynamic>.from(a as Map)));
      }
      for (final l in (meta['extras'] as List? ?? const [])) {
        _extras.add(LigneDoc.depuisJson(Map<String, dynamic>.from(l as Map)));
      }
      _remise.text = nombreChamp(num0(meta['remise_pct']));
      _tva.text = nombreChamp(num0(d['taux_tva']));
      if (meta['acompte_pct'] != null) _acomptePct.text = nombreChamp(num0(meta['acompte_pct']));
      _livraison = lireDate(meta['date_livraison']) ?? _livraison;
      _priorite = meta['priorite'] as String? ?? 'normale';
      _notes.text = d['notes'] as String? ?? '';
      _chargerClient(d['client_id'] as String);
    } else if (widget.client != null) {
      _client = widget.client;
      _chargerMesures();
    }
  }

  Future<void> _chargerClient(String id) async {
    try {
      final c = await supa.from('clients').select().eq('id', id).single();
      if (!mounted) return;
      setState(() => _client = c);
      _chargerMesures();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  Future<void> _chargerMesures() async {
    if (_client == null) return;
    try {
      final rows = await supa
          .from('mesures')
          .select('valeurs')
          .eq('client_id', _client!['id'] as String)
          .order('prise_le', ascending: false)
          .limit(1);
      if (mounted) {
        setState(() => _mesuresClient =
            rows.isEmpty ? null : Mesures.depuisJson(rows.first['valeurs'] as Map<String, dynamic>?).valeurs);
      }
    } catch (_) {}
  }

  List<LigneDoc> get _lignes => [for (final a in _articles) ...a.lignes(_unite), ..._extras];

  Totaux get _totaux => calculerTotaux(
        _lignes,
        remisePct: lireNombre(_remise.text) ?? 0,
        tauxTva: lireNombre(_tva.text) ?? 0,
        acomptePct: lireNombre(_acomptePct.text) ?? 0,
        decimales: _dec,
      );

  Future<void> _choisirClient() async {
    final c = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ClientsScreen(modeSelection: true)),
    );
    if (c == null) return;
    setState(() {
      _client = c;
      _mesuresClient = null;
    });
    _chargerMesures();
  }

  Future<void> _editerArticle([int? index]) async {
    final a = await Navigator.of(context).push<ArticleCommande>(MaterialPageRoute(
      builder: (_) => ArticleFormScreen(
        article: index == null ? null : _articles[index],
        mesures: _mesuresClient,
        nomClient: _client?['nom'] as String?,
      ),
    ));
    if (a == null) return;
    setState(() {
      if (index == null) {
        _articles.add(a);
      } else {
        _articles[index] = a;
      }
    });
  }

  Future<void> _ajouterFourniture() async {
    final art = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => const StockScreen(
        modeSelection: true,
        categories: {'fil', 'bouton', 'fermeture', 'entoilage', 'accessoire', 'doublure', 'autre'},
      ),
    ));
    if (art == null || !mounted) return;
    final l = await _dialogueLigne(LigneDoc(
      type: 'fourniture',
      designation: art['nom'] as String,
      quantite: 1,
      unite: art['unite'] as String? ?? 'pce',
      prixUnitaire: num0(art['prix_vente']),
      articleStockId: art['id'] as String,
    ));
    if (l != null) setState(() => _extras.add(l));
  }

  Future<void> _ajouterLigneLibre([int? index]) async {
    final l = await _dialogueLigne(index == null
        ? LigneDoc(type: 'option', designation: '', quantite: 1, unite: 'forfait', prixUnitaire: 0)
        : _extras[index]);
    if (l == null) return;
    setState(() {
      if (index == null) {
        _extras.add(l);
      } else {
        _extras[index] = l;
      }
    });
  }

  Future<LigneDoc?> _dialogueLigne(LigneDoc base) {
    final des = TextEditingController(text: base.designation);
    final qte = TextEditingController(text: nombreChamp(base.quantite));
    final unite = TextEditingController(text: base.unite);
    final prix = TextEditingController(text: nombreChamp(base.prixUnitaire));
    final form = GlobalKey<FormState>();
    return showDialog<LigneDoc>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(base.type == 'fourniture' ? 'Fourniture' : 'Option / autre prestation'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: des,
                decoration: const InputDecoration(labelText: 'Désignation *', hintText: 'ex : Broderie, Urgence 48 h'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: ChampNombre(controller: qte, label: 'Quantité', obligatoire: true)),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: unite, decoration: const InputDecoration(labelText: 'Unité'))),
              ]),
              const SizedBox(height: 12),
              ChampNombre(controller: prix, label: 'Prix unitaire', suffixe: Session.instance.devise, obligatoire: true),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(
                c,
                LigneDoc(
                  type: base.type,
                  designation: des.text.trim(),
                  quantite: lireNombre(qte.text) ?? 1,
                  unite: unite.text.trim(),
                  prixUnitaire: lireNombre(prix.text) ?? 0,
                  articleStockId: base.articleStockId,
                ),
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _choisirDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _livraison ?? aujourdhui(),
      firstDate: aujourdhui().subtract(const Duration(days: 365)),
      lastDate: aujourdhui().add(const Duration(days: 730)),
    );
    if (d != null) setState(() => _livraison = d);
  }

  Future<void> _enregistrer() async {
    if (_client == null) {
      snack(context, 'Choisissez un client', erreur: true);
      return;
    }
    if (_lignes.isEmpty) {
      snack(context, 'Ajoutez au moins un vêtement ou une prestation', erreur: true);
      return;
    }
    final tot = _totaux;
    final acompte = _commande ? (lireNombre(_acompteRecu.text) ?? 0) : 0.0;
    if (acompte > tot.total) {
      snack(context, 'L\'acompte reçu dépasse le total', erreur: true);
      return;
    }
    setState(() => _occupe = true);
    final s = Session.instance;
    final meta = {
      'articles': [for (final a in _articles) a.toJson()],
      'extras': [for (final l in _extras) l.toJson()],
      'remise_pct': lireNombre(_remise.text) ?? 0,
      'acompte_pct': lireNombre(_acomptePct.text) ?? 0,
      'date_livraison': _livraison == null ? null : isoDate(_livraison!),
      'priorite': _priorite,
    };
    final doc = {
      'atelier_id': s.atelierId,
      'client_id': _client!['id'],
      'lignes': [for (final l in _lignes) l.toJson()],
      'sous_total': tot.sousTotal,
      'remise_montant': tot.remise,
      'taux_tva': lireNombre(_tva.text) ?? 0,
      'montant_tva': tot.tva,
      'total': tot.total,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'meta': meta,
    };
    try {
      if (!_commande) {
        final Map<String, dynamic> res;
        if (widget.devis != null) {
          res = await supa.from('documents').update(doc).eq('id', widget.devis!['id'] as String).select().single();
        } else {
          res = await supa
              .from('documents')
              .insert({
                ...doc,
                'type': 'devis',
                'statut': 'brouillon',
                'date_echeance': isoDate(aujourdhui().add(Duration(days: s.validiteDevis))),
              })
              .select()
              .single();
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DocumentDetailScreen(documentId: res['id'] as String)),
        );
        return;
      }

      final commande = await supa
          .from('commandes')
          .insert({
            'atelier_id': s.atelierId,
            'client_id': _client!['id'],
            'date_livraison': meta['date_livraison'],
            'priorite': _priorite,
            'articles': meta['articles'],
            'total': tot.total,
            'notes': doc['notes'],
          })
          .select()
          .single();
      final facture = await supa
          .from('documents')
          .insert({
            ...doc,
            'type': 'facture',
            'statut': 'impayee',
            'commande_id': commande['id'],
            'date_echeance': meta['date_livraison'],
          })
          .select()
          .single();
      if (acompte > 0) {
        await supa.from('paiements').insert({
          'atelier_id': s.atelierId,
          'document_id': facture['id'],
          'montant': acompte,
          'mode': _modePaiement,
          'reference': 'Acompte à la commande',
        });
      }
      if (widget.devis != null) {
        await supa
            .from('documents')
            .update({'statut': 'accepte', 'commande_id': commande['id']})
            .eq('id', widget.devis!['id'] as String);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => CommandeDetailScreen(commandeId: commande['id'] as String)),
      );
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tot = _totaux;
    if (_commande && !_acompteModifie) _acompteRecu.text = nombreChamp(tot.acompte);
    final titre = _commande
        ? (widget.devis != null ? 'Commande depuis ${widget.devis!['numero']}' : 'Nouvelle commande')
        : (widget.devis != null ? 'Modifier ${widget.devis!['numero']}' : 'Nouveau devis');
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Section(titre: 'Client', children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person),
            title: Text(_client?['nom'] as String? ?? 'Choisir un client *'),
            subtitle: _client == null
                ? null
                : Text(_mesuresClient == null ? 'Pas de mesures enregistrées' : 'Mesures disponibles pour le calcul'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _choisirClient,
          ),
        ]),
        Section(
          titre: 'Vêtements',
          action: TextButton.icon(onPressed: () => _editerArticle(), icon: const Icon(Icons.add), label: const Text('Ajouter')),
          children: [
            if (_articles.isEmpty) const Text('Ajoutez les vêtements à confectionner.'),
            for (var i = 0; i < _articles.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${_articles[i].designation} ×${_articles[i].quantite}'),
                subtitle: Text([
                  'Façon ${argent(_articles[i].prixFacon)}',
                  if (_articles[i].tissuSource == 'client' && _articles[i].metrage > 0)
                    'Tissu client : ${quantiteTissu(_articles[i].metrage)}',
                  if (_articles[i].tissuSource == 'atelier')
                    'Tissu ${_articles[i].tissuNom ?? ''} : ${quantiteTissu(_articles[i].metrage)}',
                ].join(' · ')),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _articles.removeAt(i)),
                ),
                onTap: () => _editerArticle(i),
              ),
          ],
        ),
        Section(titre: 'Fournitures et options', children: [
          for (var i = 0; i < _extras.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_extras[i].designation),
              subtitle: Text('${nombre(_extras[i].quantite)} ${_extras[i].unite} × ${argent(_extras[i].prixUnitaire)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(argent(_extras[i].montant)),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _extras.removeAt(i)),
                ),
              ]),
              onTap: () => _ajouterLigneLibre(i),
            ),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _ajouterFourniture,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Fourniture du stock'),
            ),
            OutlinedButton.icon(
              onPressed: () => _ajouterLigneLibre(),
              icon: const Icon(Icons.add),
              label: const Text('Option / autre'),
            ),
          ]),
        ]),
        Section(titre: 'Conditions', children: [
          Row(children: [
            Expanded(
              child: ChampNombre(controller: _remise, label: 'Remise', suffixe: '%', onChanged: (_) => setState(() {})),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChampNombre(controller: _tva, label: 'TVA', suffixe: '%', onChanged: (_) => setState(() {})),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChampNombre(
                controller: _acomptePct,
                label: 'Acompte',
                suffixe: '%',
                onChanged: (_) => setState(() => _acompteModifie = false),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('Livraison prévue : ${dateCourte(_livraison)}'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: _choisirDate,
          ),
          if (_commande)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Commande urgente'),
              value: _priorite == 'urgente',
              onChanged: (v) => setState(() => _priorite = v ? 'urgente' : 'normale'),
            ),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (visibles sur le document)'),
          ),
        ]),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: t.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _ligneTotal('Sous-total', argent(tot.sousTotal)),
              if (tot.remise > 0) _ligneTotal('Remise', '- ${argent(tot.remise)}'),
              if (tot.tva > 0) _ligneTotal('TVA', argent(tot.tva)),
              const Divider(),
              _ligneTotal('Total', argent(tot.total), gras: true),
              _ligneTotal('Acompte demandé', argent(tot.acompte)),
            ]),
          ),
        ),
        if (_commande)
          Section(titre: 'Acompte reçu maintenant', children: [
            Row(children: [
              Expanded(
                child: ChampNombre(
                  controller: _acompteRecu,
                  label: 'Montant reçu',
                  suffixe: Session.instance.devise,
                  onChanged: (_) => _acompteModifie = true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _modePaiement,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: [
                    for (final e in modesPaiement.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _modePaiement = v ?? 'especes'),
                ),
              ),
            ]),
          ]),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _occupe ? null : _enregistrer,
            icon: _occupe
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_commande ? Icons.check_circle : Icons.request_quote),
            label: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_commande ? 'Créer la commande et la facture' : 'Enregistrer le devis'),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _ligneTotal(String libelle, String valeur, {bool gras = false}) {
    final style = gras
        ? Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(libelle, style: style)), Text(valeur, style: style)]),
    );
  }
}
