import 'dart:math' as math;

import 'vetements.dart';

/// Position d'une pièce sur le tissu déplié (cm, origine en haut à gauche).
class Placement {
  const Placement(this.libelle, this.x, this.y, this.largeur, this.hauteur, this.pivote);

  final String libelle;
  final double x;
  final double y;
  final double largeur;
  final double hauteur;
  final bool pivote;
}

class ResultatPlacement {
  const ResultatPlacement({
    required this.tissu,
    required this.largeurTissu,
    required this.placements,
    required this.longueurCoupe,
    required this.marge,
    required this.avertissements,
  });

  final TypeTissu tissu;
  final double largeurTissu;
  final List<Placement> placements;

  /// Longueur de tissu occupée par les pièces (cm).
  final double longueurCoupe;

  /// Marge de sécurité : rétrécissement au lavage, raccord de motif, droit fil (cm).
  final double marge;
  final List<String> avertissements;

  double get longueurTotale => longueurCoupe + marge;

  /// Part du tissu réellement utilisée par les pièces (0 à 1).
  double get rendement {
    if (longueurCoupe <= 0) return 0;
    final surface = placements.fold<double>(0, (s, p) => s + p.largeur * p.hauteur);
    return surface / (longueurCoupe * largeurTissu);
  }

  /// Quantité à acheter, arrondie au quart supérieur, dans l'unité demandée.
  double quantite(String unite) => arrondiQuart(convertirCm(longueurTotale, unite));
}

const cmParYard = 91.44;

double convertirCm(double cm, String unite) => unite == 'yd' ? cm / cmParYard : cm / 100;

double arrondiQuart(double v) {
  if (v <= 0) return 0;
  return ((v * 4) - 1e-9).ceilToDouble() / 4;
}

String _cm(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _Element {
  _Element(this.libelle, this.w, this.h, this.pivote);
  final String libelle;
  final double w;
  final double h;
  final bool pivote;
}

class _Colonne {
  _Colonne(this.x, this.w, this.utilise);
  final double x;
  final double w;
  double utilise;
}

class _Etagere {
  _Etagere(this.y, this.h);
  final double y;
  final double h;
  double xLibre = 0;
  final colonnes = <_Colonne>[];
}

/// Valeur de couture ajoutée de chaque côté quand une pièce est coupée en panneaux.
const _raccord = 1.5;

/// Place les pièces d'un tissu donné en « étagères » (plus hautes d'abord),
/// en empilant les petites pièces sous les grandes quand la place le permet.
ResultatPlacement placerPieces(
  List<Piece> pieces,
  TypeTissu tissu,
  double largeurTissu, {
  double espace = 1,
  double margePct = 5,
  double margeMin = 10,
}) {
  final avertissements = <String>[];
  final elements = <_Element>[];

  for (final p in pieces) {
    if (p.tissu != tissu || p.quantite <= 0 || p.largeur <= 0 || p.hauteur <= 0) continue;

    var w = p.largeur;
    var h = p.hauteur;
    var pivote = false;
    if (p.pivotable) {
      // Grand côté en travers si possible : cela économise de la longueur.
      final grand = math.max(w, h);
      final petit = math.min(w, h);
      final (nw, nh) = grand <= largeurTissu ? (grand, petit) : (petit, grand);
      pivote = nw != p.largeur;
      w = nw;
      h = nh;
    }

    var panneaux = 1;
    if (w > largeurTissu) {
      panneaux = (w / (largeurTissu - 2 * _raccord)).ceil();
      w = math.min(largeurTissu, arrondiDemi(w / panneaux + 2 * _raccord));
      avertissements.add('« ${p.zone} » (${_cm(p.largeur)} cm) est plus large que le tissu '
          '(${_cm(largeurTissu)} cm) : à couper en $panneaux panneaux de ${_cm(w)} cm, '
          'coutures de raccord comprises.');
    }

    for (var i = 1; i <= p.quantite; i++) {
      for (var k = 1; k <= panneaux; k++) {
        var libelle = p.zone;
        if (p.quantite > 1) libelle += ' $i';
        if (panneaux > 1) libelle += ' (panneau $k/$panneaux)';
        elements.add(_Element(libelle, w, h, pivote));
      }
    }
  }

  elements.sort((a, b) {
    final c = b.h.compareTo(a.h);
    return c != 0 ? c : b.w.compareTo(a.w);
  });

  const eps = 1e-6;
  final etageres = <_Etagere>[];
  final placements = <Placement>[];
  var y = 0.0;

  for (final e in elements) {
    Placement? pl;
    for (final et in etageres) {
      // 1) Sous une pièce déjà posée dans cette étagère.
      for (final col in et.colonnes) {
        if (e.w <= col.w + eps && col.utilise + e.h <= et.h + eps) {
          pl = Placement(e.libelle, col.x, et.y + col.utilise, e.w, e.h, e.pivote);
          col.utilise += e.h + espace;
          break;
        }
      }
      if (pl != null) break;
      // 2) À droite, s'il reste de la largeur.
      if (et.xLibre + e.w <= largeurTissu + eps && e.h <= et.h + eps) {
        pl = Placement(e.libelle, et.xLibre, et.y, e.w, e.h, e.pivote);
        et.colonnes.add(_Colonne(et.xLibre, e.w, e.h + espace));
        et.xLibre += e.w + espace;
        break;
      }
    }
    if (pl == null) {
      final et = _Etagere(y, e.h);
      pl = Placement(e.libelle, 0, y, e.w, e.h, e.pivote);
      et.colonnes.add(_Colonne(0, e.w, e.h + espace));
      et.xLibre = e.w + espace;
      etageres.add(et);
      y += e.h + espace;
    }
    placements.add(pl);
  }

  final longueur = etageres.isEmpty ? 0.0 : y - espace;
  final marge = longueur <= 0 ? 0.0 : math.max(margeMin, longueur * margePct / 100);

  return ResultatPlacement(
    tissu: tissu,
    largeurTissu: largeurTissu,
    placements: placements,
    longueurCoupe: longueur,
    marge: arrondiDemi(marge),
    avertissements: avertissements,
  );
}
