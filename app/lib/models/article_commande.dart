import '../calcul/calcul.dart';
import '../calcul/devis.dart';

/// Un vêtement commandé : façon, tissu (fourni par le client ou l'atelier)
/// et calcul de coupe éventuel.
class ArticleCommande {
  ArticleCommande({
    required this.designation,
    this.typeCode,
    this.quantite = 1,
    this.prixFacon = 0,
    this.tissuSource = 'client',
    this.tissuArticleId,
    this.tissuNom,
    this.tissuPrix = 0,
    this.metrage = 0,
    this.tissuClient,
    this.calcul,
  });

  factory ArticleCommande.depuisJson(Map<String, dynamic> j) => ArticleCommande(
        designation: j['designation'] as String? ?? '',
        typeCode: j['type'] as String?,
        quantite: (j['quantite'] as num?)?.toInt() ?? 1,
        prixFacon: (j['prix_facon'] as num?)?.toDouble() ?? 0,
        tissuSource: j['tissu_source'] as String? ?? 'client',
        tissuArticleId: j['tissu_article_id'] as String?,
        tissuNom: j['tissu_nom'] as String?,
        tissuPrix: (j['tissu_prix'] as num?)?.toDouble() ?? 0,
        metrage: (j['metrage'] as num?)?.toDouble() ?? 0,
        tissuClient: j['tissu_client'] as String?,
        calcul: j['calcul'] == null
            ? null
            : CalculSauvegarde.depuisJson(Map<String, dynamic>.from(j['calcul'] as Map)),
      );

  String designation;
  String? typeCode;
  int quantite;
  double prixFacon;

  /// client : le client apporte son tissu ; atelier : pris dans le stock ; aucun.
  String tissuSource;
  String? tissuArticleId;
  String? tissuNom;
  double tissuPrix;

  /// Quantité totale de tissu principal pour toutes les pièces (unité de l'atelier).
  double metrage;

  /// Description du tissu déposé par le client (couleur, motif, quantité remise…).
  String? tissuClient;
  CalculSauvegarde? calcul;

  List<LigneDoc> lignes(String unite) => [
        LigneDoc(
          type: 'facon',
          designation: 'Façon - $designation',
          quantite: quantite.toDouble(),
          unite: 'pce',
          prixUnitaire: prixFacon,
        ),
        if (tissuSource == 'atelier' && metrage > 0)
          LigneDoc(
            type: 'tissu',
            designation: 'Tissu ${tissuNom ?? ''} ($designation)'.trim(),
            quantite: metrage,
            unite: unite,
            prixUnitaire: tissuPrix,
            articleStockId: tissuArticleId,
          ),
      ];

  Map<String, dynamic> toJson() => {
        'designation': designation,
        'type': typeCode,
        'quantite': quantite,
        'prix_facon': prixFacon,
        'tissu_source': tissuSource,
        'tissu_article_id': tissuArticleId,
        'tissu_nom': tissuNom,
        'tissu_prix': tissuPrix,
        'metrage': metrage,
        'tissu_client': tissuClient,
        'calcul': calcul?.toJson(),
      };
}
