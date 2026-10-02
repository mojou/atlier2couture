import 'mesures.dart';

enum TypeTissu { principal, doublure, entoilage }

const libellesTissu = {
  TypeTissu.principal: 'Tissu principal',
  TypeTissu.doublure: 'Doublure',
  TypeTissu.entoilage: 'Entoilage',
};

/// Une pièce à découper : rectangle englobant, marges de couture et ourlet compris.
class Piece {
  const Piece(
    this.zone,
    this.quantite,
    this.largeur,
    this.hauteur, {
    this.pivotable = false,
    this.tissu = TypeTissu.principal,
    this.note,
  });

  factory Piece.depuisJson(Map<String, dynamic> j) => Piece(
        j['zone'] as String,
        (j['quantite'] as num).toInt(),
        (j['largeur'] as num).toDouble(),
        (j['hauteur'] as num).toDouble(),
        pivotable: j['pivotable'] as bool? ?? false,
        tissu: TypeTissu.values.byName(j['tissu'] as String? ?? 'principal'),
        note: j['note'] as String?,
      );

  final String zone;
  final int quantite;

  /// Largeur en travers du tissu (cm).
  final double largeur;

  /// Hauteur dans le sens du droit fil, c'est-à-dire la longueur du tissu (cm).
  final double hauteur;

  /// Petite pièce qui peut être tournée d'un quart de tour (col, poignet, ceinture…).
  final bool pivotable;
  final TypeTissu tissu;
  final String? note;

  Piece copyWith({
    String? zone,
    int? quantite,
    double? largeur,
    double? hauteur,
    bool? pivotable,
    TypeTissu? tissu,
    String? note,
  }) =>
      Piece(
        zone ?? this.zone,
        quantite ?? this.quantite,
        largeur ?? this.largeur,
        hauteur ?? this.hauteur,
        pivotable: pivotable ?? this.pivotable,
        tissu: tissu ?? this.tissu,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'zone': zone,
        'quantite': quantite,
        'largeur': largeur,
        'hauteur': hauteur,
        'pivotable': pivotable,
        'tissu': tissu.name,
        if (note != null) 'note': note,
      };
}

class OptionsCoupe {
  const OptionsCoupe({
    required this.aisance,
    this.couture = 1.5,
    this.ourlet = 4,
    this.doublure = false,
    this.ampleur = 150,
  });

  /// Aisance ajoutée au tour principal (cm).
  final double aisance;

  /// Valeur de couture de chaque côté (cm).
  final double couture;

  /// Rentré d'ourlet en bas (cm).
  final double ourlet;
  final bool doublure;

  /// Largeur d'une face de boubou (cm).
  final double ampleur;
}

class TypeVetement {
  const TypeVetement({
    required this.code,
    required this.nom,
    required this.requises,
    this.optionnelles = const [],
    required this.aisanceDefaut,
    required this.generer,
  });

  final String code;
  final String nom;
  final List<String> requises;
  final List<String> optionnelles;
  final double aisanceDefaut;
  final List<Piece> Function(Mesures m, OptionsCoupe o) generer;

  bool get aDesManches => optionnelles.contains('longueur_manche') || requises.contains('longueur_manche');
}

/// Arrondi au demi-centimètre supérieur.
double arrondiDemi(double x) => (x * 2 - 1e-9).ceilToDouble() / 2;

double _max(double a, double b) => a > b ? a : b;

// ---------------------------------------------------------------------------
// Règles de coupe par type de vêtement
// ---------------------------------------------------------------------------

List<Piece> _chemise(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final tour = m['tour_poitrine'] + o.aisance;
  final long = m['longueur_haut'];
  final manche = m['longueur_manche'];
  final longues = manche >= 40;
  final poignet = m.a('tour_poignet') ? m['tour_poignet'] : 18.0;
  final cou = m['tour_cou'];
  return [
    Piece('Devant', 2, arrondiDemi(tour / 4 + 3 + 2 * c), arrondiDemi(long + c + o.ourlet),
        note: 'Patte de boutonnage comprise'),
    Piece('Dos', 1, arrondiDemi(tour / 2 + 4 + 2 * c), arrondiDemi(long + c + o.ourlet),
        note: "Pli d'aisance au milieu du dos"),
    Piece('Empiècement', 2, arrondiDemi(m['carrure'] + 2 + 2 * c), arrondiDemi(10 + 2 * c),
        pivotable: true),
    if (manche > 0)
      Piece('Manche', 2, arrondiDemi(m['tour_bras'] + 10 + 2 * c),
          arrondiDemi(longues ? manche - 6 + 2 * c : manche + c + 3)),
    if (longues)
      Piece('Poignet', 4, arrondiDemi(poignet + 5 + 2 * c), arrondiDemi(6 + 2 * c),
          pivotable: true,
          note: m.a('tour_poignet') ? null : 'Tour de poignet non renseigné : 18 cm par défaut'),
    Piece('Col', 2, arrondiDemi(cou + 3 + 2 * c), arrondiDemi(5 + 2 * c), pivotable: true),
    Piece('Pied de col', 2, arrondiDemi(cou + 3 + 2 * c), arrondiDemi(3.5 + 2 * c), pivotable: true),
    Piece('Poche poitrine', 1, arrondiDemi(14 + 2 * c), arrondiDemi(15 + c + 3), pivotable: true),
    Piece('Col + pied de col', 2, arrondiDemi(cou + 3 + 2 * c), arrondiDemi(5 + 2 * c),
        pivotable: true, tissu: TypeTissu.entoilage),
    if (longues)
      Piece('Poignets', 2, arrondiDemi(poignet + 5 + 2 * c), arrondiDemi(6 + 2 * c),
          pivotable: true, tissu: TypeTissu.entoilage),
  ];
}

List<Piece> _haut(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final tour = _max(m['tour_poitrine'], m['tour_bassin']) + o.aisance;
  final long = m['longueur_haut'];
  final manche = m['longueur_manche'];
  final cou = m.a('tour_cou') ? m['tour_cou'] : 38.0;
  return [
    Piece('Devant', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c + o.ourlet)),
    Piece('Dos', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c + o.ourlet)),
    if (manche > 0)
      Piece('Manche', 2, arrondiDemi(m['tour_bras'] + 8 + 2 * c), arrondiDemi(manche + c + 3)),
    Piece("Parementure d'encolure", 2, arrondiDemi(cou / 2 + 12), 14, pivotable: true),
    if (o.doublure) ...[
      Piece('Devant', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c), tissu: TypeTissu.doublure),
      Piece('Dos', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c), tissu: TypeTissu.doublure),
    ],
  ];
}

List<Piece> _pantalon(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final bassin = m['tour_bassin'];
  var devant = (bassin + o.aisance) / 4 + bassin / 20;
  var dos = (bassin + o.aisance) / 4 + bassin / 10 + 2;
  String? noteCuisse;
  // La jambe doit pouvoir contenir la cuisse avec un minimum d'aisance.
  if (m.a('tour_cuisse') && devant + dos < m['tour_cuisse'] + 6) {
    final manque = m['tour_cuisse'] + 6 - (devant + dos);
    devant += manque / 2;
    dos += manque / 2;
    noteCuisse = 'Élargi pour le tour de cuisse';
  }
  final long = m['longueur_pantalon'];
  return [
    Piece('Devant', 2, arrondiDemi(devant + 2 * c), arrondiDemi(long + c + o.ourlet), note: noteCuisse),
    Piece('Dos', 2, arrondiDemi(dos + 2 * c), arrondiDemi(long + 4 + c + o.ourlet),
        note: 'Remontée de dos comprise'),
    Piece('Ceinture', 1, arrondiDemi(m['tour_taille'] + 6 + 2 * c), arrondiDemi(8 + 2 * c),
        pivotable: true),
    Piece('Parementure de braguette', 2, 8, 22, pivotable: true),
    Piece('Passants (bande)', 1, 60, 5, pivotable: true),
    Piece('Fond de poche', 4, 18, 30, pivotable: true, tissu: TypeTissu.doublure),
  ];
}

List<Piece> _jupe(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final tour = m['tour_bassin'] + o.aisance;
  final long = m['longueur_jupe'];
  return [
    Piece('Devant', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c + o.ourlet)),
    Piece('Dos', 2, arrondiDemi(tour / 4 + 2 * c), arrondiDemi(long + c + o.ourlet),
        note: 'Fermeture au milieu du dos'),
    Piece('Ceinture', 1, arrondiDemi(m['tour_taille'] + 4 + 2 * c), arrondiDemi(8 + 2 * c),
        pivotable: true),
    if (o.doublure) ...[
      Piece('Devant', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long - 3 + c), tissu: TypeTissu.doublure),
      Piece('Dos', 2, arrondiDemi(tour / 4 + 2 * c), arrondiDemi(long - 3 + c), tissu: TypeTissu.doublure),
    ],
  ];
}

List<Piece> _robe(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final tour = _max(m['tour_poitrine'], m['tour_bassin']) + o.aisance;
  final long = m['longueur_robe'];
  final manche = m['longueur_manche'];
  return [
    Piece('Devant', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c + o.ourlet)),
    Piece('Dos', 2, arrondiDemi(tour / 4 + 2 * c), arrondiDemi(long + c + o.ourlet),
        note: 'Fermeture au milieu du dos'),
    if (manche > 0)
      Piece('Manche', 2, arrondiDemi(m['tour_bras'] + 8 + 2 * c), arrondiDemi(manche + c + 3)),
    Piece("Parementure d'encolure", 2, 32, 15, pivotable: true),
    if (o.doublure) ...[
      Piece('Devant', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long - 3 + c), tissu: TypeTissu.doublure),
      Piece('Dos', 2, arrondiDemi(tour / 4 + 2 * c), arrondiDemi(long - 3 + c), tissu: TypeTissu.doublure),
    ],
  ];
}

List<Piece> _boubou(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final long = m['longueur_haut'];
  final ampleur = _max(o.ampleur, m['tour_poitrine'] / 2 + 20);
  return [
    Piece('Devant', 1, arrondiDemi(ampleur + 2 * c), arrondiDemi(long + c + o.ourlet),
        note: "D'un poignet à l'autre, bras écartés"),
    Piece('Dos', 1, arrondiDemi(ampleur + 2 * c), arrondiDemi(long + c + o.ourlet)),
    Piece("Plastron / parementure d'encolure", 2, 35, 45, pivotable: true),
    Piece('Poche', 1, 22, 28, pivotable: true),
  ];
}

List<Piece> _veste(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final tour = m['tour_poitrine'] + o.aisance;
  final long = m['longueur_haut'];
  final manche = m['longueur_manche'];
  final bras = m['tour_bras'] + 8;
  final cou = m['tour_cou'];
  return [
    Piece('Devant', 2, arrondiDemi(tour / 4 + 8 + 2 * c), arrondiDemi(long + c + o.ourlet),
        note: 'Croisure comprise'),
    Piece('Dos', 2, arrondiDemi(tour / 4 + 2 * c), arrondiDemi(long + c + o.ourlet)),
    Piece('Dessus de manche', 2, arrondiDemi(bras * 0.6 + 2 * c), arrondiDemi(manche + c + 4)),
    Piece('Dessous de manche', 2, arrondiDemi(bras * 0.4 + 2 * c), arrondiDemi(manche + c + 4)),
    Piece('Col', 2, arrondiDemi(cou / 2 + 10), 10, pivotable: true),
    Piece('Parementure devant', 2, 12, arrondiDemi(long + c)),
    Piece('Rabat de poche', 2, 18, 8, pivotable: true),
    Piece('Devant', 2, arrondiDemi(tour / 4 + 2 * c), arrondiDemi(long + c), tissu: TypeTissu.doublure),
    Piece('Dos', 2, arrondiDemi(tour / 4 + 2 * c), arrondiDemi(long + c), tissu: TypeTissu.doublure),
    Piece('Manche', 2, arrondiDemi(bras + 2 * c), arrondiDemi(manche + c), tissu: TypeTissu.doublure),
    Piece('Devant', 2, arrondiDemi(tour / 4 + 8 + 2 * c), arrondiDemi(long + c),
        tissu: TypeTissu.entoilage),
    Piece('Col', 2, arrondiDemi(cou / 2 + 10), 10, pivotable: true, tissu: TypeTissu.entoilage),
  ];
}

// ---------------------------------------------------------------------------
// Tenues d'Afrique centrale et de l'Ouest
// ---------------------------------------------------------------------------

/// Kaba (kaba ngondo) : robe très ample, manches larges, volant facultatif en bas.
List<Piece> _kaba(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final tour = _max(m['tour_poitrine'], m['tour_bassin']) + o.aisance;
  final long = m['longueur_robe'];
  final manche = m['longueur_manche'];
  return [
    Piece('Devant', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c + o.ourlet),
        note: 'Coupe évasée vers le bas'),
    Piece('Dos', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c + o.ourlet)),
    if (manche > 0)
      Piece('Manche ample', 2, arrondiDemi(m['tour_bras'] + 24 + 2 * c), arrondiDemi(manche + c + 3)),
    Piece("Parementure d'encolure", 2, 34, 16, pivotable: true),
    Piece('Poche', 2, 20, 24, pivotable: true),
  ];
}

/// Toghu : tunique ample des Grassfields (velours brodé), manches larges.
List<Piece> _toghu(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final tour = _max(m['tour_poitrine'], m['tour_bassin']) + o.aisance;
  final long = m['longueur_haut'];
  final manche = m['longueur_manche'];
  return [
    Piece('Devant', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c + o.ourlet),
        note: 'Velours : couper toutes les pièces dans le même sens du poil'),
    Piece('Dos', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c + o.ourlet)),
    if (manche > 0)
      Piece('Manche', 2, arrondiDemi(m['tour_bras'] + 18 + 2 * c), arrondiDemi(manche + c + 4),
          note: 'Bas de manche brodé'),
    Piece("Plastron brodé / parementure d'encolure", 2, 36, 42),
    if (o.doublure) ...[
      Piece('Devant', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c), tissu: TypeTissu.doublure),
      Piece('Dos', 1, arrondiDemi(tour / 2 + 2 * c), arrondiDemi(long + c), tissu: TypeTissu.doublure),
    ],
  ];
}

/// Sokoto : pantalon large et droit, taille à coulisse ou élastiquée.
List<Piece> _sokoto(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final bassin = m['tour_bassin'];
  final long = m['longueur_pantalon'];
  final devant = (bassin + o.aisance) / 4 + bassin / 16;
  final dos = (bassin + o.aisance) / 4 + bassin / 10 + 2;
  return [
    Piece('Devant', 2, arrondiDemi(devant + 2 * c), arrondiDemi(long + 4 + c + o.ourlet),
        note: 'Rentré de coulisse compris'),
    Piece('Dos', 2, arrondiDemi(dos + 2 * c), arrondiDemi(long + 6 + c + o.ourlet)),
    Piece('Poche', 2, 18, 26, pivotable: true),
  ];
}

/// Agbada : très grande robe de dessus (souvent portée sur une tunique et un sokoto).
List<Piece> _agbada(Mesures m, OptionsCoupe o) {
  final c = o.couture;
  final long = m['longueur_haut'];
  final ampleur = _max(o.ampleur, 170);
  return [
    Piece('Devant', 1, arrondiDemi(ampleur + 2 * c), arrondiDemi(long + c + o.ourlet),
        note: "D'un poignet à l'autre, bras écartés"),
    Piece('Dos', 1, arrondiDemi(ampleur + 2 * c), arrondiDemi(long + c + o.ourlet)),
    Piece('Plastron brodé', 2, 40, 55),
    Piece('Poche poitrine', 1, 22, 26, pivotable: true),
  ];
}

final typesVetements = <TypeVetement>[
  TypeVetement(
    code: 'chemise',
    nom: 'Chemise',
    requises: ['tour_cou', 'carrure', 'tour_poitrine', 'longueur_haut'],
    optionnelles: ['longueur_manche', 'tour_bras', 'tour_poignet'],
    aisanceDefaut: 10,
    generer: _chemise,
  ),
  TypeVetement(
    code: 'haut',
    nom: 'Haut / tunique / kaftan',
    requises: ['tour_poitrine', 'longueur_haut'],
    optionnelles: ['tour_bassin', 'tour_cou', 'longueur_manche', 'tour_bras'],
    aisanceDefaut: 8,
    generer: _haut,
  ),
  TypeVetement(
    code: 'pantalon',
    nom: 'Pantalon',
    requises: ['tour_taille', 'tour_bassin', 'longueur_pantalon'],
    optionnelles: ['tour_cuisse', 'bas_pantalon'],
    aisanceDefaut: 4,
    generer: _pantalon,
  ),
  TypeVetement(
    code: 'jupe',
    nom: 'Jupe droite',
    requises: ['tour_taille', 'tour_bassin', 'longueur_jupe'],
    aisanceDefaut: 4,
    generer: _jupe,
  ),
  TypeVetement(
    code: 'robe',
    nom: 'Robe',
    requises: ['tour_poitrine', 'tour_bassin', 'longueur_robe'],
    optionnelles: ['tour_taille', 'longueur_manche', 'tour_bras'],
    aisanceDefaut: 6,
    generer: _robe,
  ),
  TypeVetement(
    code: 'boubou',
    nom: 'Boubou / grand boubou',
    requises: ['tour_poitrine', 'longueur_haut'],
    aisanceDefaut: 0,
    generer: _boubou,
  ),
  TypeVetement(
    code: 'veste',
    nom: 'Veste doublée',
    requises: ['tour_cou', 'carrure', 'tour_poitrine', 'longueur_haut', 'longueur_manche', 'tour_bras'],
    aisanceDefaut: 12,
    generer: _veste,
  ),
  TypeVetement(
    code: 'kaba',
    nom: 'Kaba (kaba ngondo)',
    requises: ['tour_poitrine', 'longueur_robe'],
    optionnelles: ['tour_bassin', 'longueur_manche', 'tour_bras'],
    aisanceDefaut: 40,
    generer: _kaba,
  ),
  TypeVetement(
    code: 'toghu',
    nom: 'Toghu (tunique des Grassfields)',
    requises: ['tour_poitrine', 'longueur_haut'],
    optionnelles: ['tour_bassin', 'longueur_manche', 'tour_bras'],
    aisanceDefaut: 30,
    generer: _toghu,
  ),
  TypeVetement(
    code: 'sokoto',
    nom: 'Sokoto (pantalon large)',
    requises: ['tour_bassin', 'longueur_pantalon'],
    aisanceDefaut: 24,
    generer: _sokoto,
  ),
  TypeVetement(
    code: 'agbada',
    nom: 'Agbada (grande robe)',
    requises: ['tour_poitrine', 'longueur_haut'],
    aisanceDefaut: 0,
    generer: _agbada,
  ),
  TypeVetement(
    code: 'perso',
    nom: 'Modèle personnalisé',
    requises: [],
    aisanceDefaut: 0,
    generer: (_, __) => const [],
  ),
];

TypeVetement? typeParCode(String? code) {
  for (final t in typesVetements) {
    if (t.code == code) return t;
  }
  return null;
}
