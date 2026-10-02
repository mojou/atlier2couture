import 'mesures.dart';
import 'placement.dart';
import 'vetements.dart';

export 'mesures.dart';
export 'placement.dart';
export 'vetements.dart';

class VetementChoisi {
  VetementChoisi(this.type, [this.quantite = 1]);

  final TypeVetement type;
  int quantite;
}

/// Mesures obligatoires manquantes pour les vêtements choisis.
List<String> mesuresManquantes(List<TypeVetement> types, Mesures m) {
  final manque = <String>{};
  for (final t in types) {
    for (final k in t.requises) {
      if (!m.a(k)) manque.add(k);
    }
    // Des manches demandées sans tour de bras : la manche ne peut pas être calculée.
    if (t.aDesManches && m.a('longueur_manche') && !m.a('tour_bras')) manque.add('tour_bras');
  }
  return manque.toList();
}

/// Ajustement : près du corps, normal, ample.
const facteursAisance = [0.5, 1.0, 1.8];
const libellesAjustement = ['Près du corps', 'Normal', 'Ample'];

List<Piece> genererPieces(
  List<VetementChoisi> vetements,
  Mesures m, {
  double facteurAisance = 1,
  double couture = 1.5,
  double ourlet = 4,
  bool doublure = false,
  double ampleur = 150,
}) {
  final res = <Piece>[];
  final plusieurs = vetements.length > 1;
  for (final v in vetements) {
    final o = OptionsCoupe(
      aisance: v.type.aisanceDefaut * facteurAisance,
      couture: couture,
      ourlet: ourlet,
      doublure: doublure,
      ampleur: ampleur,
    );
    for (final p in v.type.generer(m, o)) {
      res.add(p.copyWith(
        zone: plusieurs ? '${v.type.nom} · ${p.zone}' : p.zone,
        quantite: p.quantite * v.quantite,
      ));
    }
  }
  return res;
}

Map<TypeTissu, ResultatPlacement> calculerPlacements(
  List<Piece> pieces,
  Map<TypeTissu, double> largeurs,
) {
  final res = <TypeTissu, ResultatPlacement>{};
  for (final t in TypeTissu.values) {
    if (!pieces.any((p) => p.tissu == t && p.quantite > 0)) continue;
    res[t] = placerPieces(pieces, t, largeurs[t] ?? 150);
  }
  return res;
}

/// Résultat de calcul conservé dans une commande (JSON).
class CalculSauvegarde {
  const CalculSauvegarde({
    required this.vetements,
    required this.mesures,
    required this.pieces,
    required this.largeurs,
    required this.unite,
    required this.quantites,
  });

  factory CalculSauvegarde.depuisJson(Map<String, dynamic> j) => CalculSauvegarde(
        vetements: [
          for (final v in (j['vetements'] as List? ?? const [])) Map<String, dynamic>.from(v as Map)
        ],
        mesures: Mesures.depuisJson(j['mesures'] as Map<String, dynamic>?).valeurs,
        pieces: [
          for (final p in (j['pieces'] as List? ?? const []))
            Piece.depuisJson(Map<String, dynamic>.from(p as Map))
        ],
        largeurs: {
          for (final e in (j['largeurs'] as Map? ?? const {}).entries)
            TypeTissu.values.byName(e.key as String): (e.value as num).toDouble()
        },
        unite: j['unite'] as String? ?? 'yd',
        quantites: {
          for (final e in (j['quantites'] as Map? ?? const {}).entries)
            TypeTissu.values.byName(e.key as String): (e.value as num).toDouble()
        },
      );

  /// [{code, nom, quantite}]
  final List<Map<String, dynamic>> vetements;
  final Map<String, double> mesures;
  final List<Piece> pieces;
  final Map<TypeTissu, double> largeurs;
  final String unite;
  final Map<TypeTissu, double> quantites;

  double get principal => quantites[TypeTissu.principal] ?? 0;

  int get nombreVetements =>
      vetements.fold<int>(0, (s, v) => s + ((v['quantite'] as num?)?.toInt() ?? 1));

  String get resume => vetements.map((v) => '${v['nom']} ×${v['quantite']}').join(', ');

  Map<TypeTissu, ResultatPlacement> recalculer() => calculerPlacements(pieces, largeurs);

  Map<String, dynamic> toJson() => {
        'vetements': vetements,
        'mesures': mesures,
        'pieces': [for (final p in pieces) p.toJson()],
        'largeurs': {for (final e in largeurs.entries) e.key.name: e.value},
        'unite': unite,
        'quantites': {for (final e in quantites.entries) e.key.name: e.value},
      };
}
