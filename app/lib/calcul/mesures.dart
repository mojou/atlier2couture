/// Définition des mesures prises sur le client (toutes en centimètres).
class MesureDef {
  const MesureDef(this.cle, this.libelle, this.groupe, this.min, this.max, [this.aide]);

  final String cle;
  final String libelle;
  final String groupe;

  /// Plage plausible : en dehors, on prévient (erreur de saisie probable).
  final double min;
  final double max;
  final String? aide;
}

const mesuresDefs = <MesureDef>[
  MesureDef('tour_cou', 'Tour de cou', 'Haut du corps', 25, 60),
  MesureDef('carrure', 'Carrure dos', 'Haut du corps', 25, 65,
      "D'une pointe d'épaule à l'autre, dans le dos"),
  MesureDef('epaule', "Longueur d'épaule", 'Haut du corps', 8, 25),
  MesureDef('tour_poitrine', 'Tour de poitrine', 'Haut du corps', 50, 200),
  MesureDef('tour_taille', 'Tour de taille', 'Haut du corps', 40, 200),
  MesureDef('tour_bras', 'Tour de bras', 'Bras', 15, 70),
  MesureDef('tour_poignet', 'Tour de poignet', 'Bras', 10, 35),
  MesureDef('longueur_manche', 'Longueur de manche', 'Bras', 5, 90,
      "De l'épaule au bas de la manche (manche courte : moins de 40 cm)"),
  MesureDef('tour_bassin', 'Tour de bassin / hanches', 'Bas du corps', 50, 220),
  MesureDef('tour_cuisse', 'Tour de cuisse', 'Bas du corps', 30, 110),
  MesureDef('bas_pantalon', 'Bas de pantalon', 'Bas du corps', 25, 80),
  MesureDef('longueur_haut', 'Longueur du haut', 'Longueurs', 30, 170,
      "Du haut de l'épaule jusqu'au bas souhaité"),
  MesureDef('longueur_robe', 'Longueur de robe', 'Longueurs', 50, 180),
  MesureDef('longueur_jupe', 'Longueur de jupe', 'Longueurs', 30, 130),
  MesureDef('longueur_pantalon', 'Longueur de pantalon', 'Longueurs', 30, 130),
];

final _parCle = {for (final m in mesuresDefs) m.cle: m};

MesureDef? defMesure(String cle) => _parCle[cle];

String libelleMesure(String cle) => _parCle[cle]?.libelle ?? cle;

/// Valeurs saisies d'un client, accessibles par clé (0 si absente).
class Mesures {
  const Mesures(this.valeurs);

  factory Mesures.depuisJson(Map<String, dynamic>? json) => Mesures({
        for (final e in (json ?? const {}).entries)
          if (e.value is num) e.key: (e.value as num).toDouble(),
      });

  final Map<String, double> valeurs;

  double operator [](String cle) => valeurs[cle] ?? 0;
  bool a(String cle) => (valeurs[cle] ?? 0) > 0;
}

/// Contrôle de vraisemblance : renvoie des avertissements (non bloquants).
List<String> valeursInhabituelles(Mesures m) {
  final res = <String>[];
  for (final e in m.valeurs.entries) {
    final d = defMesure(e.key);
    if (d == null || e.value <= 0) continue;
    if (e.value < d.min || e.value > d.max) {
      res.add('${d.libelle} : ${e.value} cm semble inhabituel '
          '(attendu entre ${d.min.toInt()} et ${d.max.toInt()} cm).');
    }
  }
  if (m.a('tour_taille') && m.a('tour_bassin') && m['tour_taille'] > m['tour_bassin'] + 30) {
    res.add('Le tour de taille dépasse largement le tour de bassin : vérifiez qu\'ils ne sont pas inversés.');
  }
  if (m.a('tour_cou') && m.a('tour_poitrine') && m['tour_cou'] >= m['tour_poitrine']) {
    res.add('Le tour de cou est plus grand que le tour de poitrine : vérifiez la saisie.');
  }
  if (m.a('tour_poignet') && m.a('tour_bras') && m['tour_poignet'] > m['tour_bras']) {
    res.add('Le tour de poignet est plus grand que le tour de bras : vérifiez la saisie.');
  }
  return res;
}
