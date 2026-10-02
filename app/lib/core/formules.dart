/// Formules d'abonnement. Les limites sont appliquées par la base de données ;
/// ces valeurs servent à l'affichage et à griser les fonctions non incluses.
class Formule {
  const Formule({
    required this.code,
    required this.nom,
    required this.prixMois,
    required this.avantages,
    this.maxUtilisateurs,
    this.maxClients,
    this.maxCommandesMois,
    this.stock = true,
    this.alarmes = true,
    this.tousModeles = true,
    this.premium = false,
  });

  final String code;
  final String nom;
  final int prixMois;
  final List<String> avantages;

  /// null = illimité
  final int? maxUtilisateurs;
  final int? maxClients;
  final int? maxCommandesMois;
  final bool stock;
  final bool alarmes;
  final bool tousModeles;

  /// Plusieurs ateliers, statistiques avancées, rappels groupés.
  final bool premium;
}

const formules = <String, Formule>{
  'gratuit': Formule(
    code: 'gratuit',
    nom: 'Gratuit',
    prixMois: 0,
    maxUtilisateurs: 1,
    maxClients: 30,
    maxCommandesMois: 15,
    stock: false,
    alarmes: false,
    tousModeles: false,
    avantages: [
      '1 utilisateur',
      '30 clients maximum',
      '15 commandes par mois',
      'Calculateur de métrage et fiche de découpe',
      'Factures modèle Classique',
      'Rendez-vous (sans alarme musicale)',
    ],
  ),
  'standard': Formule(
    code: 'standard',
    nom: 'Standard',
    prixMois: 5000,
    maxUtilisateurs: 3,
    avantages: [
      '3 utilisateurs',
      'Clients et commandes illimités',
      'Les 5 modèles de facture, sans mention',
      'Stock complet et alertes',
      'Alarmes musicales des rendez-vous',
    ],
  ),
  'premium': Formule(
    code: 'premium',
    nom: 'Premium',
    prixMois: 10000,
    premium: true,
    avantages: [
      'Utilisateurs illimités',
      'Tout le contenu Standard',
      'Plusieurs ateliers / boutiques',
      'Rappels WhatsApp groupés',
      'Statistiques avancées',
      'Support prioritaire',
    ],
  ),
};

/// Pays où SasPay encaisse en franc CFA : code → (nom, devise).
const paysPaiement = <String, (String, String)>{
  'CM': ('Cameroun', 'XAF'),
  'CI': ('Côte d\'Ivoire', 'XOF'),
  'SN': ('Sénégal', 'XOF'),
  'BJ': ('Bénin', 'XOF'),
  'BF': ('Burkina Faso', 'XOF'),
  'ML': ('Mali', 'XOF'),
  'NE': ('Niger', 'XOF'),
  'TG': ('Togo', 'XOF'),
};

const dureesAbonnement = [1, 3, 6, 12];
