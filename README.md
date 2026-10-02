# Atelier Couture

Application de gestion d'ateliers de couture, **multi-ateliers** : chaque atelier ne voit que ses propres données.
Elle fonctionne sur Android, iOS et navigateur web (Flutter + Supabase).

## Fonctionnalités

| Module | Ce qu'il fait |
|---|---|
| **Atelier** | Création avec logo, nom, slogan, coordonnées, NIF/RCCM, devise, unité (yards ou mètres), largeur de tissu, TVA, acompte, conditions de facture, couleur des documents. |
| **Équipe** | Rôles propriétaire, gérant, couturier et caissier. Seuls le propriétaire et le gérant peuvent supprimer ou modifier les réglages. |
| **Clients et mesures** | 15 mesures standard avec historique. Les valeurs incohérentes sont signalées (taille/bassin inversés, valeur hors plage…). |
| **Calculateur de métrage** | Chemise, haut/tunique, pantalon, jupe, robe, boubou, veste doublée, kaba, toghu, sokoto, agbada, modèle personnalisé, et ensembles. Découpe **zone par zone** (coutures et ourlets compris), **plan de coupe dessiné**, quantité à acheter en yd ou en m, doublure et entoilage séparés, alerte si une pièce dépasse la largeur du tissu, **fiche de découpe PDF**. |
| **Commandes** | Façon + tissu (apporté par le client ou pris dans le stock) + fournitures + options, remise, TVA et acompte calculés automatiquement. Suivi de production : Nouvelle → Découpe → Couture → Essayage → Finitions → Prête → Livrée. Couturier assigné, retards signalés, priorité urgente. |
| **Stock** | Tissus, doublures, fils, boutons, fermetures… Entrées, sorties et inventaire, alerte stock bas. Déduction automatique au passage en découpe. |
| **Devis et factures** | PDF avec logo et informations de l'atelier, numérotation automatique (FAC-2026-0001), **montant en lettres**, acomptes et reste à payer. Partage par WhatsApp. |
| **Paiements** | Espèces, Mobile Money, carte, virement. Le statut de la facture (payée, partielle, impayée) se met à jour tout seul. |
| **Rendez-vous** | Prise de mesures, essayage, livraison. **Alarme qui joue une musique du téléphone** à l'heure choisie par le responsable. Rappel WhatsApp au client. |
| **Tableau de bord** | Commandes en cours et en retard, rendez-vous du jour, encaissé du mois, impayés, stock bas. |

## Installation

### 1. Base de données (Supabase)

1. Créez un projet gratuit sur [supabase.com](https://supabase.com).
2. Ouvrez **SQL Editor**, collez le contenu de [supabase/migrations/20260928000000_schema_initial.sql](supabase/migrations/20260928000000_schema_initial.sql), puis cliquez sur **Run**.
3. Dans **Project Settings → API**, notez l'**URL** du projet et la clé **anon public**.
4. Pour tester sans confirmation d'e-mail : **Authentication → Providers → Email**, désactivez « Confirm email ».

### 2. Flutter

1. Installez Flutter : <https://docs.flutter.dev/get-started/install/windows>.
2. Dans le dossier `app/`, générez les dossiers des plateformes, puis installez les dépendances :

   ```bash
   cd app
   flutter create . --platforms=android,ios,web --org com.atelier
   flutter pub get
   flutter test
   ```

3. **Android, pour les alarmes** : suivez la section *Android setup* du package [alarm](https://pub.dev/packages/alarm) (version 4.x). Elle explique les permissions et le service à ajouter dans `android/app/src/main/AndroidManifest.xml`, notamment :

   ```xml
   <uses-permission android:name="android.permission.WAKE_LOCK"/>
   <uses-permission android:name="android.permission.VIBRATE"/>
   <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
   <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
   <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
   <uses-permission android:name="android.permission.INTERNET"/>
   ```

   Dans `android/app/build.gradle`, mettez `minSdkVersion 23` au minimum.

4. **iOS** : suivez la section *iOS setup* du package alarm (Background Modes : *Audio* et *Background fetch*).

### 3. Lancer l'application

```bash
flutter run --dart-define=SUPABASE_URL=https://VOTRE-PROJET.supabase.co --dart-define=SUPABASE_ANON_KEY=VOTRE_CLE_ANON
```

Pour générer l'APK Android :

```bash
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## Abonnements et paiement SasPay

| Formule | Prix | Contenu |
|---|---|---|
| Gratuit | 0 | 1 utilisateur, 30 clients, 15 commandes/mois, facture Classique avec mention, pas de stock ni d'alarmes |
| Standard | 5 000 FCFA/mois | 3 utilisateurs, illimité, 5 modèles de facture, stock, alarmes musicales |
| Premium | 10 000 FCFA/mois | Utilisateurs illimités, plusieurs ateliers, statistiques avancées, rappels WhatsApp groupés |

Les limites sont appliquées par la base de données. La clé secrète SasPay reste côté serveur, dans des Edge Functions Supabase.

1. Exécutez [supabase/migrations/20261001000000_abonnements.sql](supabase/migrations/20261001000000_abonnements.sql) dans le SQL Editor.
2. Sur **app.saspay.me**, récupérez votre **clé secrète** (`sk_test_…` pour tester, `sk_live_…` en production).
3. Dans Supabase, ouvrez **Edge Functions → Secrets** et ajoutez :
   - `SASPAY_SECRET_KEY` : la clé secrète SasPay ;
   - `SASPAY_WEBHOOK_SECRET` : le secret affiché à l'étape 5 ;
   - `SASPAY_RETURN_URL` (facultatif) : la page affichée après le paiement, par exemple l'adresse de votre site.
4. Dans **Edge Functions → Deploy a new function → Via Editor**, créez 3 fonctions avec **exactement** ces noms, en collant le contenu du fichier correspondant :
   - `saspay-checkout` ← [supabase/functions/saspay-checkout/index.ts](supabase/functions/saspay-checkout/index.ts)
   - `saspay-verifier` ← [supabase/functions/saspay-verifier/index.ts](supabase/functions/saspay-verifier/index.ts)
   - `saspay-webhook` ← [supabase/functions/saspay-webhook/index.ts](supabase/functions/saspay-webhook/index.ts). Pour celle-ci, **désactivez « Verify JWT »** (« Enforce JWT verification ») dans ses paramètres.
5. Sur **app.saspay.me**, créez un **webhook** pointant vers `https://<projet>.supabase.co/functions/v1/saspay-webhook`, pour les événements `transaction.*`. Copiez le **secret** affiché (il n'est montré qu'une fois) dans `SASPAY_WEBHOOK_SECRET`.

Le webhook déclenche seulement une revérification : l'abonnement n'est activé qu'après confirmation directe auprès de SasPay. Sans webhook, l'application vérifie aussi le paiement au retour de la page SasPay.

## Photos, caisse, paie, suivi client, exports

Exécutez [supabase/migrations/20261003000000_photos_caisse_suivi.sql](supabase/migrations/20261003000000_photos_caisse_suivi.sql) dans le SQL Editor.

- **Photos de commande** : modèle, tissu, essayage, vêtement fini. Bucket privé `photos`, accès par liens temporaires.
- **Lien de suivi client** : `https://<site>/suivi.html?c=<jeton>`. Le client voit l'avancement sans compte (fonction `suivi_commande`).
- **Caisse** : dépenses par catégorie, encaissements, bénéfice du mois.
- **Paie des couturiers** : à la pièce ou en pourcentage de la façon, par mois. Les versements sont enregistrés en dépenses « Salaires ».
- **Exports CSV**, lisibles par Excel : clients, commandes, devis et factures, paiements, dépenses, stock.

## Clé de signature Android (IMPORTANT)

Les fichiers `app/android/upload-keystore.jks` et `app/android/key.properties` (qui contient le mot de passe) signent l'application.
Ils sont **volontairement exclus de git**.

**Sauvegardez-les** dans un endroit sûr (clé USB, Google Drive privé). Sans eux, il est impossible de publier une mise à jour sur le Play Store.

Paquet pour le Play Store : `flutter build appbundle --release --dart-define-from-file=config.json`.

## Premier démarrage

1. Créez votre compte, puis votre atelier (logo, infos de facturation, unité yards ou mètres).
2. **Plus → Catalogue de modèles** : ajoutez vos modèles et leurs prix de façon.
3. **Plus → Stock** : ajoutez vos tissus et fournitures avec leur prix de vente.
4. **Clients** : créez un client et prenez ses mesures.
5. **Nouvelle commande** : ajoutez un vêtement, puis **Calculer** pour obtenir le métrage. La facture est créée avec la commande.
6. **Plus → Sonnerie des rendez-vous** : choisissez la musique par défaut des alarmes.
7. **Plus → Équipe** : ajoutez vos employés. Ils doivent d'abord créer leur compte avec leur e-mail.

## Structure

```
supabase/migrations/     Schéma SQL, sécurité par atelier (RLS), numérotation, triggers
app/lib/calcul/          Moteur de calcul (mesures, pièces, placement, devis, montant en lettres)
app/lib/pdf/             Factures, devis, fiches de découpe
app/lib/services/        Alarmes musicales des rendez-vous
app/lib/screens/         Écrans
app/test/                Tests du moteur de calcul
```

## Sécurité multi-ateliers

- Chaque table porte un `atelier_id`.
- Les règles de sécurité PostgreSQL (RLS) n'autorisent l'accès qu'aux membres de l'atelier, même si quelqu'un appelle l'API directement.
- Les suppressions sont réservées au propriétaire et au gérant.

## À savoir

- **Les règles de coupe sont des estimations standard**, avec des rectangles englobants et une marge de sécurité de 5 % (10 cm minimum). Chaque pièce reste modifiable avant le calcul final, et le calculateur accepte des pièces personnalisées.
- **Les alarmes sonnent sur le téléphone**, pas dans le navigateur. Chaque téléphone de l'équipe reprogramme les alarmes des rendez-vous à venir quand l'application s'ouvre.
- **Pistes pour la suite** : photos des modèles et du tissu déposé, mode hors connexion, rappels SMS automatiques, dépenses de l'atelier, paie à la pièce des couturiers.
