/// Ligne de devis ou de facture.
class LigneDoc {
  LigneDoc({
    required this.type,
    required this.designation,
    required this.quantite,
    required this.unite,
    required this.prixUnitaire,
    this.articleStockId,
  });

  factory LigneDoc.depuisJson(Map<String, dynamic> j) => LigneDoc(
        type: j['type'] as String? ?? 'autre',
        designation: j['designation'] as String? ?? '',
        quantite: (j['quantite'] as num?)?.toDouble() ?? 0,
        unite: j['unite'] as String? ?? '',
        prixUnitaire: (j['prix_unitaire'] as num?)?.toDouble() ?? 0,
        articleStockId: j['article_stock_id'] as String?,
      );

  /// facon, tissu, fourniture, option, autre
  String type;
  String designation;
  double quantite;
  String unite;
  double prixUnitaire;

  /// Article du stock à déduire au moment de la découpe.
  String? articleStockId;

  double get montant => quantite * prixUnitaire;

  Map<String, dynamic> toJson() => {
        'type': type,
        'designation': designation,
        'quantite': quantite,
        'unite': unite,
        'prix_unitaire': prixUnitaire,
        'montant': montant,
        if (articleStockId != null) 'article_stock_id': articleStockId,
      };
}

class Totaux {
  const Totaux({
    required this.sousTotal,
    required this.remise,
    required this.tva,
    required this.total,
    required this.acompte,
  });

  final double sousTotal;
  final double remise;
  final double tva;
  final double total;
  final double acompte;
}

double arrondiMonnaie(double v, int decimales) {
  if (decimales <= 0) return v.roundToDouble();
  final f = decimales == 1 ? 10 : 100;
  return (v * f).roundToDouble() / f;
}

Totaux calculerTotaux(
  List<LigneDoc> lignes, {
  double remisePct = 0,
  double tauxTva = 0,
  double acomptePct = 0,
  int decimales = 0,
}) {
  final sousTotal = arrondiMonnaie(lignes.fold<double>(0, (s, l) => s + l.montant), decimales);
  final remise = arrondiMonnaie(sousTotal * remisePct.clamp(0, 100) / 100, decimales);
  final base = sousTotal - remise;
  final tva = arrondiMonnaie(base * tauxTva / 100, decimales);
  final total = base + tva;
  final acompte = arrondiMonnaie(total * acomptePct.clamp(0, 100) / 100, decimales);
  return Totaux(sousTotal: sousTotal, remise: remise, tva: tva, total: total, acompte: acompte);
}
