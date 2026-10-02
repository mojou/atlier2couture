import 'dart:io';

import 'package:atelier_couture/calcul/calcul.dart';
import 'package:atelier_couture/core/session.dart';
import 'package:atelier_couture/pdf/documents_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    Session.instance.definir({
      'id': 'a1',
      'nom': 'Atelier Élégance',
      'slogan': 'Le sur-mesure à votre image',
      'adresse': 'Rue des Tailleurs',
      'ville': 'Douala',
      'pays': 'Cameroun',
      'telephone': '+237 6 00 00 00 00',
      'email': 'contact@exemple.cm',
      'identifiant_fiscal': 'M0123456789',
      'registre_commerce': 'RC/DLA/2026/B/123',
      'devise': 'FCFA',
      'unite_tissu': 'yd',
      'couleur': '#7B2D8E',
      'conditions_facture': 'Acompte de 50 % à la commande.',
      'pied_facture': 'Merci de votre confiance !',
    }, 'proprietaire');
  });

  for (final modele in modelesFacture.keys) {
    test('facture PDF modèle $modele', () async {
      final octets = await genererDocumentPdf(
        modele: modele,
        doc: {
          'type': 'facture',
          'numero': 'FAC-2026-0001',
          'statut': 'partielle',
          'date_emission': '2026-09-28',
          'date_echeance': '2026-10-05',
          'lignes': [
            {
              'type': 'facon',
              'designation': 'Façon - Boubou brodé',
              'quantite': 1,
              'unite': 'pce',
              'prix_unitaire': 25000
            },
            {
              'type': 'tissu',
              'designation': 'Tissu Bazin riche (Boubou)',
              'quantite': 5.75,
              'unite': 'yd',
              'prix_unitaire': 3500
            },
          ],
          'sous_total': 45125,
          'remise_montant': 0,
          'taux_tva': 0,
          'montant_tva': 0,
          'total': 45125,
          'montant_paye': 20000,
          'notes': 'Broderie dorée « style Dakar ».',
          'meta': {'date_livraison': '2026-10-05', 'acompte_pct': 50},
        },
        client: {'nom': 'Aïcha Ngono', 'telephone': '+237 6 11 22 33 44'},
        paiements: [
          {
            'paye_le': '2026-09-28T10:00:00Z',
            'mode': 'mobile_money',
            'reference': 'OM-123',
            'montant': 20000
          },
        ],
      );
      expect(octets.length, greaterThan(1000));
      File('build/test_facture_$modele.pdf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(octets);
    });
  }

  test('fiche de découpe PDF', () async {
    const m = Mesures({
      'tour_cou': 40,
      'carrure': 46,
      'tour_poitrine': 100,
      'longueur_haut': 78,
      'longueur_manche': 62,
      'tour_bras': 34
    });
    final pieces = genererPieces([VetementChoisi(typeParCode('chemise')!)], m);
    final largeurs = {
      TypeTissu.principal: 150.0,
      TypeTissu.doublure: 150.0,
      TypeTissu.entoilage: 90.0
    };
    final res = calculerPlacements(pieces, largeurs);
    final octets = await genererFicheDecoupePdf(
      calcul: CalculSauvegarde(
        vetements: [
          {'code': 'chemise', 'nom': 'Chemise', 'quantite': 1}
        ],
        mesures: m.valeurs,
        pieces: pieces,
        largeurs: largeurs,
        unite: 'yd',
        quantites: {for (final e in res.entries) e.key: e.value.quantite('yd')},
      ),
      client: 'Aïcha Ngono',
    );
    expect(octets.length, greaterThan(1000));
  });
}
