import 'package:flutter/material.dart';

import 'formules.dart';
import 'theme.dart';

export 'formules.dart';

/// Atelier courant (tenant) et rôle de l'utilisateur dans cet atelier.
class Session extends ChangeNotifier {
  Session._();
  static final instance = Session._();

  Map<String, dynamic>? _atelier;
  String _role = 'couturier';

  /// Administrateur de la plateforme (gère tous les ateliers).
  bool superAdmin = false;

  bool get aAtelier => _atelier != null;
  Map<String, dynamic> get atelier => _atelier ?? const {};
  String get atelierId => atelier['id'] as String;
  String get role => _role;
  bool get estGestionnaire => _role == 'proprietaire' || _role == 'gerant';

  String get devise {
    final d = (atelier['devise'] as String?)?.trim();
    return (d == null || d.isEmpty) ? 'FCFA' : d;
  }

  /// Les francs CFA et le franc guinéen ne s'écrivent pas avec des centimes.
  int get decimales =>
      const {'FCFA', 'F CFA', 'CFA', 'XOF', 'XAF', 'GNF'}.contains(devise.toUpperCase()) ? 0 : 2;

  String get unite => (atelier['unite_tissu'] as String?) ?? 'yd';
  String get uniteLong => unite == 'yd' ? 'yards' : 'mètres';
  double get largeurTissu => _nombre('largeur_tissu_cm', 150);
  double get tauxTva => _nombre('taux_tva', 0);
  double get acomptePct => _nombre('acompte_pct', 50);
  int get validiteDevis => (atelier['validite_devis_jours'] as num?)?.toInt() ?? 30;
  Color get couleur => couleurDepuisHex(atelier['couleur'] as String?);
  /// essai, en_attente, actif ou suspendu. Absent (ancienne base) : considéré actif.
  String get statut => (atelier['statut'] as String?) ?? 'actif';

  /// Fin de la période d'essai (statut « essai »).
  DateTime? get essaiFin {
    final v = atelier['essai_fin'] as String?;
    return v == null ? null : DateTime.parse(v).toLocal();
  }

  bool get enEssai => statut == 'essai' && (essaiFin?.isAfter(DateTime.now()) ?? false);
  bool get essaiExpire => statut == 'essai' && !enEssai;

  /// L'atelier peut utiliser l'application (même règle que la base de données).
  bool get accessible => statut == 'actif' || enEssai;
  /// Formule en vigueur : une formule payante expirée redevient Gratuite.
  String get formule {
    final f = (atelier['formule'] as String?) ?? 'gratuit';
    final fin = formuleFin;
    if (f == 'gratuit' || fin == null || !fin.isAfter(DateTime.now())) return 'gratuit';
    return f;
  }

  DateTime? get formuleFin {
    final v = atelier['formule_fin'] as String?;
    return v == null ? null : DateTime.parse(v).toLocal();
  }

  Formule get offre => formules[formule] ?? formules['gratuit']!;

  String get modeleFacture => (atelier['modele_facture'] as String?) ?? 'classique';

  double _nombre(String cle, double defaut) => (atelier[cle] as num?)?.toDouble() ?? defaut;

  void definir(Map<String, dynamic> atelier, String role) {
    _atelier = atelier;
    _role = role;
    notifyListeners();
  }

  void majAtelier(Map<String, dynamic> atelier) {
    _atelier = atelier;
    notifyListeners();
  }

  void vider() {
    _atelier = null;
    notifyListeners();
  }
}
