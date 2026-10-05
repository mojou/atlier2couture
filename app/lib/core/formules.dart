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
    this.questionsAssistantJour = 10,
    this.standard = true,
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
  final int questionsAssistantJour;

  /// Fonctions de la formule Standard : messagerie interne, photos, lien de
  /// suivi client, stock, caisse, exports, alarmes, 5 modèles de facture.
  final bool standard;

  /// Fonctions Premium : paie des couturiers, statistiques avancées, rappels
  /// groupés, plusieurs ateliers.
  final bool premium;

  bool get messagerie => standard;
  bool get photos => standard;
  bool get suiviClient => standard;
  bool get stock => standard;
  bool get caisse => standard;
  bool get exports => standard;
  bool get alarmes => standard;
  bool get tousModeles => standard;
  bool get paie => premium;
}

const formules = <String, Formule>{
  'gratuit': Formule(
    code: 'gratuit',
    nom: 'Gratuit',
    prixMois: 0,
    maxUtilisateurs: 1,
    maxClients: 30,
    maxCommandesMois: 15,
    questionsAssistantJour: 10,
    standard: false,
    avantages: [
      '1 utilisateur',
      '30 clients et leurs mesures',
      '15 commandes par mois',
      'Calculateur de métrage',
      'Factures modèle Classique',
      'Agenda des rendez-vous',
      'Assistant : 10 questions par jour',
    ],
  ),
  'standard': Formule(
    code: 'standard',
    nom: 'Standard',
    prixMois: 5000,
    maxUtilisateurs: 3,
    questionsAssistantJour: 50,
    avantages: [
      '3 utilisateurs',
      'Clients et commandes illimités',
      'Messagerie interne de l\'équipe',
      'Photos des modèles et du tissu',
      'Lien de suivi pour le client',
      'Stock, caisse et exports Excel',
      'Alarmes musicales des rendez-vous',
      '5 modèles de facture, sans mention',
    ],
  ),
  'premium': Formule(
    code: 'premium',
    nom: 'Premium',
    prixMois: 10000,
    questionsAssistantJour: 150,
    premium: true,
    avantages: [
      'Utilisateurs illimités',
      'Tout le contenu Standard',
      'Paie des couturiers',
      'Statistiques avancées',
      'Rappels WhatsApp groupés',
      'Plusieurs ateliers / boutiques',
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
