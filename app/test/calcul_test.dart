import 'package:atelier_couture/calcul/calcul.dart';
import 'package:atelier_couture/calcul/devis.dart';
import 'package:atelier_couture/calcul/lettres.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const homme = Mesures({
    'tour_cou': 40,
    'carrure': 46,
    'tour_poitrine': 100,
    'tour_taille': 88,
    'tour_bassin': 102,
    'tour_bras': 34,
    'tour_poignet': 18,
    'longueur_manche': 62,
    'longueur_haut': 78,
    'longueur_pantalon': 104,
  });

  group('Mesures', () {
    test('signale les mesures obligatoires manquantes', () {
      final manque = mesuresManquantes([typeParCode('pantalon')!], const Mesures({'tour_taille': 80}));
      expect(manque, containsAll(['tour_bassin', 'longueur_pantalon']));
    });

    test('exige le tour de bras quand il y a des manches', () {
      const m = Mesures({'tour_poitrine': 90, 'longueur_haut': 70, 'longueur_manche': 30});
      expect(mesuresManquantes([typeParCode('haut')!], m), contains('tour_bras'));
    });

    test('détecte une valeur hors plage', () {
      expect(valeursInhabituelles(const Mesures({'tour_poitrine': 950})), isNotEmpty);
      expect(valeursInhabituelles(homme), isEmpty);
    });
  });

  group('Pièces', () {
    test('chemise manches longues : zones attendues', () {
      final pieces = genererPieces([VetementChoisi(typeParCode('chemise')!)], homme);
      final zones = pieces.map((p) => p.zone).toSet();
      expect(zones, containsAll(['Devant', 'Dos', 'Manche', 'Poignet', 'Col', 'Pied de col']));
      final devant = pieces.firstWhere((p) => p.zone == 'Devant');
      // (100 + 10) / 4 + 3 + 2 × 1,5 = 33,5 cm ; 78 + 1,5 + 4 = 83,5 cm
      expect(devant.largeur, 33.5);
      expect(devant.hauteur, 83.5);
      expect(devant.quantite, 2);
    });

    test('la quantité de vêtements multiplie les pièces', () {
      final pieces = genererPieces([VetementChoisi(typeParCode('pantalon')!, 3)], homme);
      expect(pieces.firstWhere((p) => p.zone == 'Devant').quantite, 6);
    });

    test('un ensemble préfixe les zones par le vêtement', () {
      final pieces = genererPieces(
        [VetementChoisi(typeParCode('chemise')!), VetementChoisi(typeParCode('pantalon')!)],
        homme,
      );
      expect(pieces.any((p) => p.zone == 'Pantalon · Ceinture'), isTrue);
    });
  });

  group('Placement', () {
    test('aucune pièce ne dépasse la largeur ni ne se chevauche', () {
      final pieces = genererPieces([VetementChoisi(typeParCode('chemise')!)], homme);
      final r = placerPieces(pieces, TypeTissu.principal, 150);
      for (final p in r.placements) {
        expect(p.x + p.largeur, lessThanOrEqualTo(150 + 1e-6));
        expect(p.y + p.hauteur, lessThanOrEqualTo(r.longueurCoupe + 1e-6));
      }
      for (var i = 0; i < r.placements.length; i++) {
        for (var j = i + 1; j < r.placements.length; j++) {
          final a = r.placements[i];
          final b = r.placements[j];
          final chevauche = a.x < b.x + b.largeur - 1e-6 &&
              b.x < a.x + a.largeur - 1e-6 &&
              a.y < b.y + b.hauteur - 1e-6 &&
              b.y < a.y + a.hauteur - 1e-6;
          expect(chevauche, isFalse, reason: '${a.libelle} / ${b.libelle}');
        }
      }
      // Une chemise homme demande classiquement entre 1,5 et 3 m en 150 cm.
      expect(r.quantite('m'), inInclusiveRange(1.5, 3));
    });

    test('une pièce trop large est coupée en panneaux avec un avertissement', () {
      final r = placerPieces(const [Piece('Dos', 1, 200, 100)], TypeTissu.principal, 115);
      expect(r.avertissements, hasLength(1));
      expect(r.placements, hasLength(2));
      expect(r.placements.every((p) => p.largeur <= 115), isTrue);
    });

    test('conversion en yards arrondie au quart supérieur', () {
      expect(arrondiQuart(convertirCm(182.88, 'yd')), 2.0);
      expect(arrondiQuart(convertirCm(183, 'yd')), 2.25);
      expect(arrondiQuart(0), 0);
    });
  });

  group('Devis', () {
    test('totaux avec remise, TVA et acompte', () {
      final t = calculerTotaux(
        [
          LigneDoc(type: 'facon', designation: 'Façon', quantite: 2, unite: 'pce', prixUnitaire: 15000),
          LigneDoc(type: 'tissu', designation: 'Tissu', quantite: 3.5, unite: 'yd', prixUnitaire: 2000),
        ],
        remisePct: 10,
        tauxTva: 18,
        acomptePct: 50,
      );
      expect(t.sousTotal, 37000);
      expect(t.remise, 3700);
      expect(t.tva, 5994);
      expect(t.total, 39294);
      expect(t.acompte, 19647);
    });
  });

  group('Montant en lettres', () {
    test('règles du français', () {
      expect(enLettres(0), 'zéro');
      expect(enLettres(21), 'vingt et un');
      expect(enLettres(71), 'soixante et onze');
      expect(enLettres(80), 'quatre-vingts');
      expect(enLettres(81), 'quatre-vingt-un');
      expect(enLettres(97), 'quatre-vingt-dix-sept');
      expect(enLettres(200), 'deux cents');
      expect(enLettres(250), 'deux cent cinquante');
      expect(enLettres(1000), 'mille');
      expect(enLettres(80000), 'quatre-vingt mille');
      expect(enLettres(200000), 'deux cent mille');
      expect(enLettres(39294), 'trente-neuf mille deux cent quatre-vingt-quatorze');
      expect(enLettres(1250000), 'un million deux cent cinquante mille');
    });
  });
}
