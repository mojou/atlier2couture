/// Assistant hors ligne, sans coût : répond aux questions fréquentes à partir
/// d'une base de questions-réponses intégrée (recherche par mots-clés).
/// Utilisé quand l'assistant IA (fonction serveur « assistant ») n'est pas installé.
class EntreeFaq {
  const EntreeFaq(this.motsCles, this.reponse, [this.reponseEn]);

  /// Mots ou expressions (sans accents, en minuscules) qui désignent le sujet.
  final List<String> motsCles;
  final String reponse;
  final String? reponseEn;
}

const _support = 'Pour toute autre aide : Plus → Contacter le support (WhatsApp +237 676 14 33 53).';

const faq = <EntreeFaq>[
  EntreeFaq(
    ['metrage', 'yard', 'yards', 'metre', 'tissu acheter', 'combien de tissu', 'calcul', 'calculer', 'calculateur', 'decoupe', 'plan de coupe'],
    'Calculer le métrage :\n'
        '1. Plus → Calculateur de métrage (ou « Calculer » dans un vêtement de commande).\n'
        '2. Touchez + pour ajouter le vêtement (chemise, robe, boubou, kaba, toghu, sokoto, agbada…) et sa quantité.\n'
        '3. Saisissez les mesures, ou touchez « Client » pour charger celles d\'un client.\n'
        '4. Choisissez la largeur du tissu (90, 115, 140, 150 cm) et l\'ajustement.\n'
        '5. « Calculer le métrage » : vous voyez la quantité à acheter, le détail pièce par pièce et le plan de coupe.\n'
        '« Fiche de découpe » crée un PDF pour le couturier.',
    'Fabric calculator: Plus → Calculateur de métrage, add the garment with +, enter the measurements (or load a client), '
        'choose the fabric width, then tap « Calculer le métrage » to get the yardage, each piece and the cutting plan.',
  ),
  EntreeFaq(
    ['kaba', 'toghu', 'sokoto', 'agbada', 'boubou', 'tenue', 'tenues', 'ensemble', 'robe', 'chemise', 'pantalon', 'jupe', 'veste'],
    'Le calculateur connaît : chemise, haut/tunique/kaftan, pantalon, jupe, robe, boubou, veste doublée, kaba, toghu, sokoto, '
        'agbada et le modèle personnalisé (vous saisissez vos pièces). Pour un ensemble (ex. agbada + haut + sokoto), '
        'ajoutez plusieurs vêtements avec le bouton +. Pour le boubou et l\'agbada, réglez l\'« ampleur ».',
  ),
  EntreeFaq(
    ['mesure', 'mesures', 'prendre les mesures', 'tour de poitrine', 'tour de taille', 'bassin'],
    'Prendre les mesures : Clients → ouvrez le client → section Mesures → « Prendre les mesures ». Toutes les mesures sont en '
        'centimètres ; ne remplissez que celles utiles. L\'application signale les valeurs bizarres (ex. taille et bassin inversés). '
        'Les anciennes mesures restent dans l\'historique.',
    'Measurements: Clients → open the client → Mesures → « Prendre les mesures ». All values are in centimetres.',
  ),
  EntreeFaq(
    ['client', 'clients', 'ajouter un client', 'nouveau client', 'add a client', 'customer'],
    'Ajouter un client : onglet Clients → « Nouveau client » → nom, téléphone (format +237 6XX XX XX XX pour WhatsApp), sexe, '
        'adresse, notes → Enregistrer. Depuis sa fiche : appeler, écrire sur WhatsApp, prendre les mesures, faire un devis ou une commande.',
    'Add a client: Clients tab → « Nouveau client » → name, phone (+237…), then save.',
  ),
  EntreeFaq(
    ['commande', 'commandes', 'nouvelle commande', 'creer une commande', 'order'],
    'Créer une commande : Accueil → « Nouvelle commande » (ou onglet Commandes → +).\n'
        '1. Choisissez le client.\n'
        '2. « Ajouter » un vêtement : modèle, quantité, prix de façon, tissu (apporté par le client ou pris dans le stock), métrage.\n'
        '3. Ajoutez fournitures ou options si besoin, la date de livraison et l\'acompte reçu.\n'
        '4. « Créer la commande et la facture ».',
    'New order: Home → « Nouvelle commande », choose the client, add garments, then « Créer la commande et la facture ».',
  ),
  EntreeFaq(
    ['etape', 'etapes', 'statut', 'production', 'couture', 'essayage', 'finitions', 'prete', 'livree', 'livrer', 'retard'],
    'Suivi de production : ouvrez la commande → « Étape suivante » (Nouvelle → Découpe → Couture → Essayage → Finitions → Prête → Livrée), '
        'ou le menu en haut à droite pour choisir l\'étape. Au passage à « Prête », l\'application propose de prévenir le client sur WhatsApp. '
        'Les commandes en retard apparaissent en rouge.',
  ),
  EntreeFaq(
    ['devis', 'quote', 'quotation'],
    'Faire un devis : Plus → Devis et factures → onglet Devis → « + Devis » (ou depuis la fiche client). Quand le client accepte, '
        'ouvrez le devis → « Le client accepte : créer la commande ».',
  ),
  EntreeFaq(
    ['facture', 'factures', 'pdf', 'imprimer', 'envoyer la facture', 'invoice', 'logo sur la facture', 'modele de facture'],
    'Factures : elles sont créées automatiquement avec chaque commande. Ouvrez-la (Plus → Devis et factures, ou depuis la commande) → '
        'icône PDF en haut → imprimer ou partager (WhatsApp…). Le PDF porte votre logo et vos informations (Plus → Paramètres de l\'atelier). '
        'En Gratuit : modèle Classique ; en Standard et Premium : 5 modèles au choix.',
    'Invoices are created with each order. Open it → PDF icon → print or share on WhatsApp.',
  ),
  EntreeFaq(
    ['paiement', 'encaisser', 'acompte', 'reste a payer', 'payer la facture', 'mobile money client', 'payment'],
    'Encaisser un client : ouvrez la facture ou la commande → « Encaisser » → montant, mode (espèces, Mobile Money, carte, virement) '
        'et référence. Le reste à payer et le statut (payée, payée en partie) se mettent à jour tout seuls.',
  ),
  EntreeFaq(
    ['rendez-vous', 'rendez vous', 'rdv', 'agenda', 'appointment', 'essayage date'],
    'Rendez-vous : onglet Agenda → « + Rendez-vous » → client, type (prise de mesures, essayage, livraison…), date, heure. '
        'Le menu de chaque rendez-vous permet d\'envoyer un rappel WhatsApp au client ou de le marquer honoré, absent ou annulé.',
  ),
  EntreeFaq(
    ['alarme', 'sonne pas', 'sonnerie', 'musique', 'reveil', 'alarm'],
    'Alarmes musicales (formule Standard, application Android) : choisissez la musique dans Plus → Sonnerie des rendez-vous, puis '
        '« Tester la sonnerie ». Si l\'alarme ne sonne pas : autorisez les notifications et les alarmes, et dans les paramètres du '
        'téléphone → Applications → Atelier Couture → Batterie → « Sans restriction » (important sur Tecno, Infinix, Itel, Xiaomi, Samsung).',
  ),
  EntreeFaq(
    ['stock', 'tissus en stock', 'inventaire', 'fournitures', 'boutons'],
    'Stock (formule Standard) : Plus → Stock → « + Article » (tissu, doublure, fil, boutons…), avec quantité, seuil d\'alerte et prix. '
        'Boutons Entrée, Sortie et Inventaire. Le tissu de l\'atelier est déduit à la découpe d\'une commande.',
  ),
  EntreeFaq(
    ['caisse', 'depense', 'depenses', 'benefice', 'profit', 'expense'],
    'Caisse (formule Standard) : Plus → Caisse et dépenses → « + Dépense ». Vous voyez pour chaque mois l\'encaissé, les dépenses par catégorie et le bénéfice.',
  ),
  EntreeFaq(
    ['paie', 'salaire', 'payer les couturiers', 'tailleur paye'],
    'Paie des couturiers (formule Premium) : Plus → Paie des couturiers → réglez le tarif de chacun (à la pièce ou en % de la façon). '
        'Les vêtements passés à « Prête » dans le mois sont comptés ; « Payer » enregistre le versement dans la caisse.',
  ),
  EntreeFaq(
    ['photo', 'photos', 'image', 'modele whatsapp'],
    'Photos (formule Standard) : ouvrez la commande → section Photos → « Ajouter » → prendre une photo ou choisir dans la galerie '
        '(ex. modèle reçu sur WhatsApp), puis indiquez si c\'est le modèle, le tissu, l\'essayage ou le vêtement fini.',
  ),
  EntreeFaq(
    ['suivi', 'lien de suivi', 'client voir', 'avancement'],
    'Lien de suivi (formule Standard) : ouvrez la commande → « Envoyer le lien de suivi au client ». Le client voit l\'étape en cours, '
        'la date de livraison et le reste à payer, sans créer de compte.',
  ),
  EntreeFaq(
    ['message', 'messages', 'messagerie', 'discussion', 'chat', 'canal'],
    'Messagerie interne (formule Standard) : onglet Messages. Canal « Général » pour toute l\'équipe, « Nouveau » pour un message privé '
        'ou un canal, et « Ouvrir la discussion » dans chaque commande. Le client ne voit pas ces messages.',
  ),
  EntreeFaq(
    ['equipe', 'employe', 'couturier', 'ajouter un membre', 'gerant', 'caissier', 'utilisateur', 'utilisateurs'],
    'Ajouter un employé : il crée d\'abord son compte dans l\'application avec son e-mail. Puis le propriétaire ou le gérant va dans '
        'Plus → Équipe → « Membre » → e-mail et rôle (gérant, couturier, caissier). Utilisateurs : 1 en Gratuit, 3 en Standard, illimité en Premium.',
  ),
  EntreeFaq(
    ['formule', 'formules', 'abonnement', 'prix', 'tarif', 'gratuit', 'standard', 'premium', 'difference', 'price', 'plan'],
    'Formules :\n'
        '- Gratuit (0) : 1 utilisateur, 30 clients, 15 commandes par mois, calculateur, factures Classique, agenda.\n'
        '- Standard (5 000 FCFA/mois) : 3 utilisateurs, illimité, messagerie interne, photos, lien de suivi, stock, caisse, exports Excel, alarmes, 5 modèles de facture.\n'
        '- Premium (10 000 FCFA/mois) : tout Standard + utilisateurs illimités, paie des couturiers, statistiques, rappels groupés, plusieurs ateliers.\n'
        'Voir et payer : Plus → Mon abonnement.',
    'Plans: Free (basic, 1 user), Standard 5,000 FCFA/month (team chat, photos, stock, cash book…), Premium 10,000 FCFA/month '
        '(tailors\' pay, statistics, several workshops). See Plus → Mon abonnement.',
  ),
  EntreeFaq(
    ['payer abonnement', 'orange money', 'mtn', 'momo', 'saspay', 'activer', 'pas active', 'renouveler'],
    'Payer l\'abonnement : Plus → Mon abonnement → choisissez le pays et la durée (1, 3, 6 ou 12 mois) → « Choisir Standard » ou « Premium » '
        '→ payez sur la page sécurisée (MTN MoMo, Orange Money…) → revenez dans l\'application : la formule s\'active. Sinon, touchez « Vérifier ». '
        'Si le paiement a été débité mais rien ne s\'active, contactez le support avec la référence.',
  ),
  EntreeFaq(
    ['limite', 'bloque', '30 clients', '15 commandes', 'ne peux plus'],
    'En formule Gratuite, vous êtes limité à 30 clients et 15 commandes par mois. Quand la limite est atteinte, passez en Standard '
        '(Plus → Mon abonnement) pour continuer sans limite. Vos données sont conservées.',
  ),
  EntreeFaq(
    ['mot de passe', 'oublie', 'connexion', 'connecter', 'password', 'login'],
    'Mot de passe oublié : sur l\'écran de connexion, saisissez votre e-mail puis « Mot de passe oublié ? ». Ouvrez le lien reçu par e-mail '
        '(regardez aussi les spams) et choisissez un nouveau mot de passe.',
    'Forgot password: type your e-mail on the login screen, tap « Mot de passe oublié ? » and open the link sent by e-mail (check spam).',
  ),
  EntreeFaq(
    ['installer', 'apk', 'android', 'telecharger', 'application telephone', 'mise a jour', 'install'],
    'Installer sur Android : sur https://atelier2couture.netlify.app touchez « Application Android », ouvrez le fichier téléchargé, '
        'autorisez l\'installation d\'applications inconnues, puis « Installer » (et « Installer quand même » si Play Protect avertit). '
        'Si Android refuse une mise à jour, désinstallez l\'ancienne version : vos données sont en ligne.',
  ),
  EntreeFaq(
    ['logo', 'parametres', 'nom de l atelier', 'adresse atelier', 'devise', 'tva', 'couleur'],
    'Paramètres de l\'atelier (propriétaire ou gérant) : Plus → Paramètres de l\'atelier → logo, nom, téléphone, adresse, NIF, RCCM, devise, '
        'unité (yards ou mètres), largeur de tissu, TVA, acompte, conditions de facture, couleur.',
  ),
  EntreeFaq(
    ['export', 'excel', 'comptable', 'csv'],
    'Exporter vers Excel (formule Standard) : Plus → Exporter mes données → clients, commandes, factures, paiements, dépenses ou stock. '
        'Le fichier s\'ouvre dans Excel et peut être envoyé par WhatsApp ou e-mail.',
  ),
  EntreeFaq(
    ['catalogue', 'modeles', 'prix de facon'],
    'Catalogue de modèles : Plus → Catalogue de modèles → « + Modèle » avec son prix de façon. Il sera proposé quand vous ajoutez un vêtement à une commande ou un devis.',
  ),
  EntreeFaq(
    ['support', 'contact', 'aide', 'probleme', 'bug', 'erreur', 'help'],
    'Contacter le support : Plus → Contacter le support, ou WhatsApp +237 676 14 33 53, ou germbob96@gmail.com. Décrivez le problème et, si possible, envoyez une capture d\'écran.',
    'Support: Plus → Contacter le support, WhatsApp +237 676 14 33 53 or germbob96@gmail.com.',
  ),
];

String _normaliser(String s) {
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', '’': ' ', '\'': ' ',
  };
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    b.write(accents[c] ?? c);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9 -]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _enAnglais(String q) {
  const mots = ['how', 'what', 'where', 'can i', 'do i', 'the', 'my', 'is', 'add', 'create', 'why', 'i'];
  final n = ' ${_normaliser(q)} ';
  return mots.where((m) => n.contains(' $m ')).length >= 2;
}

/// Meilleure réponse de la base pour la question, ou un message d'orientation.
String repondreFaq(String question) {
  final q = ' ${_normaliser(question)} ';
  EntreeFaq? meilleure;
  var meilleurScore = 0;
  for (final e in faq) {
    var score = 0;
    for (final m in e.motsCles) {
      final cle = _normaliser(m);
      // Mot entier, ou début de mot pour les mots longs (« facture » trouve « factures »).
      if (q.contains(' $cle ') || (cle.length > 4 && q.contains(' $cle'))) score += cle.contains(' ') ? 3 : 2;
    }
    if (score > meilleurScore) {
      meilleurScore = score;
      meilleure = e;
    }
  }
  final anglais = _enAnglais(question);
  if (meilleure == null) {
    return anglais
        ? 'I did not find an answer to that question. Try other words (e.g. "order", "invoice", "fabric calculator"), '
            'or contact support: WhatsApp +237 676 14 33 53.'
        : 'Je n\'ai pas trouvé de réponse à cette question. Essayez avec d\'autres mots (ex. « commande », « facture », '
            '« métrage », « formule »), ou contactez le support : WhatsApp +237 676 14 33 53.';
  }
  final reponse = anglais && meilleure.reponseEn != null ? meilleure.reponseEn! : meilleure.reponse;
  return '$reponse\n\n$_support';
}
