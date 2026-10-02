import 'package:flutter/material.dart';

import '../calcul/calcul.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../pdf/documents_pdf.dart';
import 'clients_screen.dart';
import 'pdf_screen.dart';
import 'plan_coupe.dart';

/// Calculateur de métrage : à partir des mesures, génère les pièces zone par
/// zone, les place sur la largeur du tissu et donne la quantité à acheter.
///
/// En mode sélection, « Utiliser ce calcul » renvoie un [CalculSauvegarde].
class CalculateurScreen extends StatefulWidget {
  const CalculateurScreen({
    super.key,
    this.mesuresInitiales,
    this.typesInitiaux,
    this.quantiteInitiale = 1,
    this.modeSelection = false,
    this.nomClient,
    this.calculInitial,
  });

  final Map<String, double>? mesuresInitiales;
  final List<String>? typesInitiaux;
  final int quantiteInitiale;
  final bool modeSelection;
  final String? nomClient;
  final CalculSauvegarde? calculInitial;

  @override
  State<CalculateurScreen> createState() => _CalculateurScreenState();
}

class _CalculateurScreenState extends State<CalculateurScreen> {
  final _vetements = <VetementChoisi>[];
  final _mesures = <String, TextEditingController>{};
  String? _nomClient;
  int _ajustement = 1;
  bool _doublure = false;
  final _couture = TextEditingController(text: '1,5');
  final _ourlet = TextEditingController(text: '4');
  final _ampleur = TextEditingController(text: '150');
  late final _largeur = TextEditingController(text: nombreChamp(Session.instance.largeurTissu));
  final _largeurDoublure = TextEditingController(text: '150');
  final _largeurEntoilage = TextEditingController(text: '90');

  List<Piece>? _pieces;
  Map<TypeTissu, ResultatPlacement>? _resultats;
  List<String> _alertesMesures = [];

  String get _unite => Session.instance.unite;

  @override
  void initState() {
    super.initState();
    _nomClient = widget.nomClient;
    final calc = widget.calculInitial;
    if (calc != null) {
      for (final v in calc.vetements) {
        final t = typeParCode(v['code'] as String?);
        if (t != null) _vetements.add(VetementChoisi(t, (v['quantite'] as num?)?.toInt() ?? 1));
      }
      _remplirMesures(calc.mesures);
      _largeur.text = nombreChamp(calc.largeurs[TypeTissu.principal] ?? Session.instance.largeurTissu);
      _largeurDoublure.text = nombreChamp(calc.largeurs[TypeTissu.doublure] ?? 150);
      _largeurEntoilage.text = nombreChamp(calc.largeurs[TypeTissu.entoilage] ?? 90);
      _pieces = [...calc.pieces];
      _resultats = calculerPlacements(_pieces!, _largeurs());
    } else {
      for (final code in widget.typesInitiaux ?? const <String>[]) {
        final t = typeParCode(code);
        if (t != null) _vetements.add(VetementChoisi(t, widget.quantiteInitiale));
      }
      _remplirMesures(widget.mesuresInitiales ?? const {});
    }
  }

  void _remplirMesures(Map<String, double> valeurs) {
    for (final e in valeurs.entries) {
      _ctrl(e.key).text = nombreChamp(e.value);
    }
  }

  TextEditingController _ctrl(String cle) => _mesures.putIfAbsent(cle, TextEditingController.new);

  Mesures _lireMesures() => Mesures({
        for (final e in _mesures.entries)
          if ((lireNombre(e.value.text) ?? 0) > 0) e.key: lireNombre(e.value.text)!,
      });

  Map<TypeTissu, double> _largeurs() => {
        TypeTissu.principal: lireNombre(_largeur.text) ?? Session.instance.largeurTissu,
        TypeTissu.doublure: lireNombre(_largeurDoublure.text) ?? 150,
        TypeTissu.entoilage: lireNombre(_largeurEntoilage.text) ?? 90,
      };

  List<String> get _clesAffichees {
    final cles = <String>{};
    for (final v in _vetements) {
      cles
        ..addAll(v.type.requises)
        ..addAll(v.type.optionnelles);
    }
    return [for (final d in mesuresDefs) if (cles.contains(d.cle)) d.cle];
  }

  Set<String> get _clesRequises => {for (final v in _vetements) ...v.type.requises};

  bool get _aBoubou => _vetements.any((v) => v.type.code == 'boubou' || v.type.code == 'agbada');

  Future<void> _chargerClient() async {
    final c = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ClientsScreen(modeSelection: true)),
    );
    if (c == null) return;
    try {
      final rows = await supa
          .from('mesures')
          .select('valeurs')
          .eq('client_id', c['id'] as String)
          .order('prise_le', ascending: false)
          .limit(1);
      if (!mounted) return;
      if (rows.isEmpty) {
        snack(context, 'Ce client n\'a pas encore de mesures', erreur: true);
        return;
      }
      setState(() {
        _nomClient = c['nom'] as String;
        for (final ctrl in _mesures.values) {
          ctrl.clear();
        }
        _remplirMesures(Mesures.depuisJson(rows.first['valeurs'] as Map<String, dynamic>?).valeurs);
      });
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  void _calculer() {
    FocusScope.of(context).unfocus();
    if (_vetements.isEmpty) {
      snack(context, 'Ajoutez au moins un vêtement', erreur: true);
      return;
    }
    final largeur = lireNombre(_largeur.text) ?? 0;
    if (largeur < 30) {
      snack(context, 'Largeur du tissu invalide', erreur: true);
      return;
    }
    final m = _lireMesures();
    final manque = mesuresManquantes([for (final v in _vetements) v.type], m);
    if (manque.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Mesures manquantes'),
          content: Text('Pour éviter une erreur de coupe, renseignez :\n\n'
              '${manque.map((k) => '• ${libelleMesure(k)}').join('\n')}'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      return;
    }
    setState(() {
      _alertesMesures = valeursInhabituelles(m);
      _pieces = genererPieces(
        _vetements,
        m,
        facteurAisance: facteursAisance[_ajustement],
        couture: lireNombre(_couture.text) ?? 1.5,
        ourlet: lireNombre(_ourlet.text) ?? 4,
        doublure: _doublure,
        ampleur: lireNombre(_ampleur.text) ?? 150,
      );
      _resultats = calculerPlacements(_pieces!, _largeurs());
    });
  }

  void _recalculer() => setState(() => _resultats = calculerPlacements(_pieces!, _largeurs()));

  Future<void> _editerPiece([int? index]) async {
    final p = await showDialog<Piece>(
      context: context,
      builder: (_) => _DialoguePiece(piece: index == null ? null : _pieces![index]),
    );
    if (p == null) return;
    _pieces ??= [];
    setState(() {
      if (index == null) {
        _pieces!.add(p);
      } else {
        _pieces![index] = p;
      }
    });
    _recalculer();
  }

  CalculSauvegarde _sauvegarde() => CalculSauvegarde(
        vetements: [
          for (final v in _vetements) {'code': v.type.code, 'nom': v.type.nom, 'quantite': v.quantite}
        ],
        mesures: _lireMesures().valeurs,
        pieces: [..._pieces!],
        largeurs: _largeurs(),
        unite: _unite,
        quantites: {for (final e in _resultats!.entries) e.key: e.value.quantite(_unite)},
      );

  void _fichePdf() {
    final calc = _sauvegarde();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfScreen(
        titre: 'Fiche de découpe',
        nomFichier: 'fiche-decoupe.pdf',
        construire: () => genererFicheDecoupePdf(calcul: calc, client: _nomClient),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final requises = _clesRequises;
    return Scaffold(
      appBar: AppBar(title: const Text('Calcul du métrage')),
      body: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        Section(
          titre: 'Vêtements',
          action: PopupMenuButton<TypeVetement>(
            tooltip: 'Ajouter un vêtement',
            icon: const Icon(Icons.add_circle),
            onSelected: (type) => setState(() => _vetements.add(VetementChoisi(type))),
            itemBuilder: (_) => [for (final t in typesVetements) PopupMenuItem(value: t, child: Text(t.nom))],
          ),
          children: [
            if (_vetements.isEmpty) const Text('Appuyez sur + pour ajouter un vêtement (un ensemble = plusieurs vêtements).'),
            for (final v in _vetements)
              Row(children: [
                Expanded(child: Text(v.type.nom)),
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: v.quantite > 1 ? () => setState(() => v.quantite--) : null,
                ),
                Text('${v.quantite}', style: t.textTheme.titleMedium),
                IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => v.quantite++)),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _vetements.remove(v)),
                ),
              ]),
          ],
        ),
        if (_clesAffichees.isNotEmpty)
          Section(
            titre: _nomClient == null ? 'Mesures (cm)' : 'Mesures de $_nomClient (cm)',
            action: TextButton.icon(
              onPressed: _chargerClient,
              icon: const Icon(Icons.person_search),
              label: const Text('Client'),
            ),
            children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final cle in _clesAffichees)
                  SizedBox(
                    width: 165,
                    child: ChampNombre(
                      controller: _ctrl(cle),
                      label: libelleMesure(cle),
                      suffixe: 'cm',
                      obligatoire: requises.contains(cle),
                    ),
                  ),
              ]),
            ],
          ),
        Section(titre: 'Tissu et coupe', children: [
          Row(children: [
            Expanded(
              child: ChampNombre(controller: _largeur, label: 'Largeur du tissu', suffixe: 'cm', obligatoire: true),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final l in const [90, 115, 140, 150])
              ActionChip(label: Text('$l cm'), onPressed: () => setState(() => _largeur.text = '$l')),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < libellesAjustement.length; i++)
                ButtonSegment(value: i, label: Text(libellesAjustement[i])),
            ],
            selected: {_ajustement},
            onSelectionChanged: (s) => setState(() => _ajustement = s.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Doublé (doublure)'),
            value: _doublure,
            onChanged: (v) => setState(() => _doublure = v),
          ),
          if (_aBoubou)
            ChampNombre(
              controller: _ampleur,
              label: 'Ampleur du boubou (une face)',
              suffixe: 'cm',
              aide: 'Largeur d\'un poignet à l\'autre, bras écartés',
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Marges et autres tissus'),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              Row(children: [
                Expanded(child: ChampNombre(controller: _couture, label: 'Couture (par côté)', suffixe: 'cm')),
                const SizedBox(width: 12),
                Expanded(child: ChampNombre(controller: _ourlet, label: 'Ourlet', suffixe: 'cm')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: ChampNombre(controller: _largeurDoublure, label: 'Largeur doublure', suffixe: 'cm')),
                const SizedBox(width: 12),
                Expanded(child: ChampNombre(controller: _largeurEntoilage, label: 'Largeur entoilage', suffixe: 'cm')),
              ]),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _calculer,
            icon: const Icon(Icons.calculate),
            label: const Padding(padding: EdgeInsets.all(10), child: Text('Calculer le métrage')),
          ),
        ]),
        if (_alertesMesures.isNotEmpty)
          Card(
            color: Colors.orange.shade50,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final a in _alertesMesures) Text('⚠ $a'),
              ]),
            ),
          ),
        if (_resultats != null) ..._vueResultats(t),
      ]),
      bottomNavigationBar: _resultats == null || _resultats!.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _fichePdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Fiche de découpe'),
                    ),
                  ),
                  if (widget.modeSelection) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, _sauvegarde()),
                        icon: const Icon(Icons.check),
                        label: const Text('Utiliser ce calcul'),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
    );
  }

  List<Widget> _vueResultats(ThemeData t) {
    final r = _resultats!;
    return [
      for (final res in r.values)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: res.tissu == TypeTissu.principal ? t.colorScheme.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${libellesTissu[res.tissu]} (largeur ${nombre(res.largeurTissu)} cm)',
                  style: t.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                res.tissu == TypeTissu.principal
                    ? 'À acheter / demander au client : ${nombre(res.quantite(_unite))} $_unite'
                    : 'À prévoir : ${nombre(res.quantite(_unite))} $_unite',
                style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_unite == 'yd' && res.tissu == TypeTissu.principal && res.quantite(_unite) > 0)
                Text('Soit ${(res.quantite(_unite) / 6).ceil()} pagne(s) de 6 yards si le tissu est vendu en pagnes.'),
              Text('Longueur de coupe ${nombre(res.longueurCoupe, max: 0)} cm + marge de sécurité '
                  '${nombre(res.marge, max: 0)} cm · tissu utilisé à ${nombre(res.rendement * 100, max: 0)} %'),
              for (final a in res.avertissements)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('⚠ $a', style: const TextStyle(color: Colors.deepOrange)),
                ),
            ]),
          ),
        ),
      Section(
        titre: 'Détail zone par zone',
        action: TextButton.icon(
          onPressed: () => _editerPiece(),
          icon: const Icon(Icons.add),
          label: const Text('Pièce'),
        ),
        children: [
          const Text('Dimensions de coupe, coutures et ourlets compris. Touchez une pièce pour la corriger.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          if (_pieces!.isEmpty) const Text('Aucune pièce. Ajoutez vos pièces avec le bouton « Pièce ».'),
          for (var i = 0; i < _pieces!.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text('${_pieces![i].quantite}', style: const TextStyle(fontSize: 12))),
              title: Text(_pieces![i].zone),
              subtitle: Text([
                '${nombre(_pieces![i].largeur)} × ${nombre(_pieces![i].hauteur)} cm',
                if (_pieces![i].tissu != TypeTissu.principal) libellesTissu[_pieces![i].tissu]!,
                if (_pieces![i].note != null) _pieces![i].note!,
              ].join(' · ')),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() => _pieces!.removeAt(i));
                  _recalculer();
                },
              ),
              onTap: () => _editerPiece(i),
            ),
        ],
      ),
      for (final res in r.values)
        if (res.placements.isNotEmpty)
          Section(
            titre: 'Plan de coupe · ${libellesTissu[res.tissu]}',
            children: [
              Text('Tissu déplié vu du dessus : largeur en travers, longueur vers le bas.',
                  style: t.textTheme.bodySmall),
              const SizedBox(height: 8),
              PlanCoupe(resultat: res, unite: _unite),
            ],
          ),
    ];
  }
}

class _DialoguePiece extends StatefulWidget {
  const _DialoguePiece({this.piece});

  final Piece? piece;

  @override
  State<_DialoguePiece> createState() => _DialoguePieceState();
}

class _DialoguePieceState extends State<_DialoguePiece> {
  final _form = GlobalKey<FormState>();
  late final _zone = TextEditingController(text: widget.piece?.zone ?? '');
  late final _qte = TextEditingController(text: '${widget.piece?.quantite ?? 1}');
  late final _l = TextEditingController(text: nombreChamp(widget.piece?.largeur));
  late final _h = TextEditingController(text: nombreChamp(widget.piece?.hauteur));
  late bool _pivot = widget.piece?.pivotable ?? false;
  late TypeTissu _tissu = widget.piece?.tissu ?? TypeTissu.principal;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.piece == null ? 'Nouvelle pièce' : 'Modifier la pièce'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _zone,
              decoration: const InputDecoration(labelText: 'Zone (ex : Devant, Manche) *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
            ),
            const SizedBox(height: 12),
            ChampNombre(controller: _qte, label: 'Nombre de pièces', obligatoire: true),
            const SizedBox(height: 12),
            ChampNombre(controller: _l, label: 'Largeur de coupe', suffixe: 'cm', obligatoire: true),
            const SizedBox(height: 12),
            ChampNombre(
              controller: _h,
              label: 'Hauteur de coupe (droit fil)',
              suffixe: 'cm',
              obligatoire: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TypeTissu>(
              initialValue: _tissu,
              decoration: const InputDecoration(labelText: 'Tissu'),
              items: [
                for (final e in libellesTissu.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _tissu = v ?? TypeTissu.principal),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _pivot,
              onChanged: (v) => setState(() => _pivot = v ?? false),
              title: const Text('Peut être tournée (pas de sens de droit fil imposé)'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final l = lireNombre(_l.text) ?? 0;
            final h = lireNombre(_h.text) ?? 0;
            final q = (lireNombre(_qte.text) ?? 1).round();
            if (l <= 0 || h <= 0 || q <= 0) return;
            Navigator.pop(
              context,
              Piece(_zone.text.trim(), q, l, h, pivotable: _pivot, tissu: _tissu, note: widget.piece?.note),
            );
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
