import 'package:flutter/material.dart';

/// Étapes de production, dans l'ordre.
const etapesProduction = ['nouvelle', 'decoupe', 'couture', 'essayage', 'finitions', 'prete', 'livree'];
const statutsEnCours = ['nouvelle', 'decoupe', 'couture', 'essayage', 'finitions', 'prete'];

const libellesStatut = {
  'nouvelle': 'Nouvelle',
  'decoupe': 'Découpe',
  'couture': 'Couture',
  'essayage': 'Essayage',
  'finitions': 'Finitions',
  'prete': 'Prête',
  'livree': 'Livrée',
  'annulee': 'Annulée',
};

Color couleurStatut(String s) => switch (s) {
      'nouvelle' => Colors.blueGrey,
      'decoupe' => Colors.orange,
      'couture' => Colors.indigo,
      'essayage' => Colors.purple,
      'finitions' => Colors.teal,
      'prete' => Colors.green,
      'livree' => Colors.grey,
      'annulee' => Colors.red,
      _ => Colors.grey,
    };

const typesRdv = {
  'prise_mesures': 'Prise de mesures',
  'essayage': 'Essayage',
  'livraison': 'Livraison',
  'retouche': 'Retouche',
  'autre': 'Autre',
};

IconData iconeRdv(String t) => switch (t) {
      'prise_mesures' => Icons.straighten,
      'essayage' => Icons.checkroom,
      'livraison' => Icons.local_shipping_outlined,
      'retouche' => Icons.content_cut,
      _ => Icons.event,
    };

const statutsRdv = {'prevu': 'Prévu', 'honore': 'Honoré', 'absent': 'Absent', 'annule': 'Annulé'};

const modesPaiement = {
  'especes': 'Espèces',
  'mobile_money': 'Mobile Money',
  'carte': 'Carte bancaire',
  'virement': 'Virement',
  'autre': 'Autre',
};

const categoriesStock = {
  'tissu': 'Tissu',
  'doublure': 'Doublure',
  'fil': 'Fil',
  'bouton': 'Boutons',
  'fermeture': 'Fermetures',
  'entoilage': 'Entoilage',
  'accessoire': 'Accessoires',
  'autre': 'Autre',
};

const unitesParCategorie = {
  'fil': 'bobine',
  'bouton': 'pce',
  'fermeture': 'pce',
  'accessoire': 'pce',
  'autre': 'pce',
};

const categoriesDepense = {
  'tissu': 'Achat de tissu',
  'fournitures': 'Fournitures',
  'loyer': 'Loyer',
  'electricite': 'Électricité / eau',
  'transport': 'Transport',
  'salaire': 'Salaires',
  'materiel': 'Matériel / machines',
  'autre': 'Autre',
};

IconData iconeDepense(String c) => switch (c) {
      'tissu' => Icons.texture,
      'fournitures' => Icons.inventory_2_outlined,
      'loyer' => Icons.home_work_outlined,
      'electricite' => Icons.bolt,
      'transport' => Icons.local_taxi_outlined,
      'salaire' => Icons.badge_outlined,
      'materiel' => Icons.precision_manufacturing_outlined,
      _ => Icons.receipt_outlined,
    };

const categoriesPhoto = {
  'modele': 'Modèle souhaité',
  'tissu': 'Tissu déposé',
  'essayage': 'Essayage',
  'resultat': 'Vêtement fini',
  'autre': 'Autre',
};

const statutsDocument = {
  'brouillon': 'Brouillon',
  'envoye': 'Envoyé',
  'accepte': 'Accepté',
  'refuse': 'Refusé',
  'impayee': 'Impayée',
  'partielle': 'Payée en partie',
  'payee': 'Payée',
  'annulee': 'Annulée',
};

Color couleurStatutDocument(String s) => switch (s) {
      'accepte' || 'payee' => Colors.green,
      'partielle' => Colors.orange,
      'impayee' => Colors.red,
      'refuse' || 'annulee' => Colors.grey,
      'envoye' => Colors.blue,
      _ => Colors.blueGrey,
    };

const roles = {
  'proprietaire': 'Propriétaire',
  'gerant': 'Gérant',
  'couturier': 'Couturier',
  'caissier': 'Caissier',
};
