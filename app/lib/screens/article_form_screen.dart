import 'package:flutter/material.dart';

import '../calcul/calcul.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/widgets.dart';
import '../models/article_commande.dart';
import 'calculateur_screen.dart';
import 'modeles_screen.dart';
import 'stock_screen.dart';

/// Ajout / modification d'un vêtement dans une commande ou un devis.
class ArticleFormScreen extends StatefulWidget {
  const ArticleFormScreen({super.key, this.article, this.mesures, this.nomClient});

  final ArticleCommande? article;
  final Map<String, double>? mesures;
  final String? nomClient;

  @override
  State<ArticleFormScreen> createState() => _ArticleFormScreenState();
}

class _ArticleFormScreenState extends State<ArticleFormScreen> {
  final _form = GlobalKey<FormState>();
  late final ArticleCommande? _a = widget.article;
  late final _designation = TextEditingController(text: _a?.designation ?? '');
  late String? _type = _a?.typeCode;
  late final _quantite = TextEditingController(text: '${_a?.quantite ?? 1}');
  late final _prixFacon = TextEditingController(text: nombreChamp(_a?.prixFacon));
  late String _source = _a?.tissuSource ?? 'client';
  late String? _tissuId = _a?.tissuArticleId;
  late String? _tissuNom = _a?.tissuNom;
  late final _tissuPrix = TextEditingController(text: nombreChamp(_a?.tissuPrix));
  late final _metrage = TextEditingController(text: nombreChamp(_a?.metrage));
  late final _tissuClient = TextEditingController(text: _a?.tissuClient ?? '');
  late CalculSauvegarde? _calcul = _a?.calcul;

  String get _unite => Session.instance.unite;
  int get _qte => (lireNombre(_quantite.text) ?? 1).round().clamp(1, 999);

  Future<void> _choisirModele() async {
    final m = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ModelesScreen(modeSelection: true)),
    );
    if (m == null) return;
    setState(() {
      _designation.text = m['nom'] as String;
      final code = m['type_vetement'] as String?;
      if (typeParCode(code) != null) _type = code;
      _prixFacon.text = nombreChamp(num0(m['prix_facon']));
    });
  }

  Future<void> _choisirTissu() async {
    final t = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const StockScreen(modeSelection: true, categories: {'tissu', 'doublure'})),
    );
    if (t == null) return;
    setState(() {
      _tissuId = t['id'] as String;
      _tissuNom = t['nom'] as String;
      _tissuPrix.text = nombreChamp(num0(t['prix_vente']));
    });
  }

  Future<void> _calculer() async {
    final c = await Navigator.of(context).push<CalculSauvegarde>(MaterialPageRoute(
      builder: (_) => CalculateurScreen(
        calculInitial: _calcul,
        mesuresInitiales: widget.mesures,
        typesInitiaux: _type == null ? null : [_type!],
        quantiteInitiale: _qte,
        modeSelection: true,
        nomClient: widget.nomClient,
      ),
    ));
    if (c == null) return;
    setState(() {
      _calcul = c;
      _metrage.text = nombreChamp(c.principal);
      if (_type == null && c.vetements.length == 1) _type = c.vetements.first['code'] as String?;
    });
  }

  void _valider() {
    if (!_form.currentState!.validate()) return;
    if (_source == 'atelier' && _tissuId == null) {
      snack(context, 'Choisissez le tissu dans le stock', erreur: true);
      return;
    }
    Navigator.pop(
      context,
      ArticleCommande(
        designation: _designation.text.trim(),
        typeCode: _type,
        quantite: _qte,
        prixFacon: lireNombre(_prixFacon.text) ?? 0,
        tissuSource: _source,
        tissuArticleId: _source == 'atelier' ? _tissuId : null,
        tissuNom: _source == 'atelier' ? _tissuNom : null,
        tissuPrix: _source == 'atelier' ? lireNombre(_tissuPrix.text) ?? 0 : 0,
        metrage: lireNombre(_metrage.text) ?? 0,
        tissuClient: _source == 'client' && _tissuClient.text.trim().isNotEmpty ? _tissuClient.text.trim() : null,
        calcul: _calcul,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final metrage = lireNombre(_metrage.text) ?? 0;
    final calculPerime = _calcul != null && _calcul!.nombreVetements != _qte;
    return Scaffold(
      appBar: AppBar(title: Text(widget.article == null ? 'Ajouter un vêtement' : 'Modifier le vêtement')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _designation,
                decoration: const InputDecoration(labelText: 'Modèle / désignation *', hintText: 'ex : Boubou brodé'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
              ),
            ),
            IconButton(tooltip: 'Catalogue', onPressed: _choisirModele, icon: const Icon(Icons.style)),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type de vêtement (pour le calcul de coupe)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('—')),
              for (final tv in typesVetements) DropdownMenuItem<String?>(value: tv.code, child: Text(tv.nom)),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ChampNombre(
                controller: _quantite,
                label: 'Quantité',
                obligatoire: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ChampNombre(
                controller: _prixFacon,
                label: 'Prix de façon (unité)',
                suffixe: Session.instance.devise,
                obligatoire: true,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Tissu', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'client', label: Text('Le client apporte')),
              ButtonSegment(value: 'atelier', label: Text('L\'atelier fournit')),
              ButtonSegment(value: 'aucun', label: Text('Sans tissu')),
            ],
            selected: {_source},
            onSelectionChanged: (s) => setState(() => _source = s.first),
          ),
          const SizedBox(height: 12),
          if (_source != 'aucun') ...[
            Row(children: [
              Expanded(
                child: ChampNombre(
                  controller: _metrage,
                  label: 'Métrage total',
                  suffixe: _unite,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: _calculer,
                icon: const Icon(Icons.straighten),
                label: Text(_calcul == null ? 'Calculer' : 'Recalculer'),
              ),
            ]),
            if (_calcul != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Calcul : ${_calcul!.resume} · ${_calcul!.pieces.length} zones'
                  '${(_calcul!.quantites[TypeTissu.doublure] ?? 0) > 0 ? ' · doublure ${nombre(_calcul!.quantites[TypeTissu.doublure])} $_unite' : ''}',
                  style: t.textTheme.bodySmall,
                ),
              ),
            if (calculPerime)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('⚠ La quantité a changé depuis le calcul : recalculez le métrage.',
                    style: TextStyle(color: Colors.deepOrange)),
              ),
          ],
          if (_source == 'client') ...[
            if (metrage > 0)
              Card(
                color: t.colorScheme.primaryContainer,
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('À demander au client : ${nombre(metrage)} $_unite de tissu',
                      style: t.textTheme.titleMedium),
                ),
              ),
            TextFormField(
              controller: _tissuClient,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Tissu déposé par le client',
                hintText: 'ex : Wax bleu à motifs, 6 yards remis le 28/09',
              ),
            ),
          ],
          if (_source == 'atelier') ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2),
              title: Text(_tissuNom ?? 'Choisir le tissu dans le stock'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _choisirTissu,
            ),
            ChampNombre(controller: _tissuPrix, label: 'Prix de vente du tissu', suffixe: '${Session.instance.devise}/$_unite'),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _valider, icon: const Icon(Icons.check), label: const Text('Valider')),
        ]),
      ),
    );
  }
}
