# Yawi — application mobile (Flutter)

Application native **Android** et **iOS** pour les passagers et les chauffeurs Yawi.
Projet indépendant du site : il se connecte à l'**API du back-office** Laravel (`https://…/api/v1`, jetons Sanctum).
Le site et l'application se déploient séparément ; seule l'adresse du serveur les relie (`YAWI_URL`).

- Identifiant : `gn.yawi.app` — nom affiché : **Yawi**
- Serveur par défaut : `https://yawi.elitegroupe-sarl.com` (modifiable à la compilation)
- Android 7.0 minimum (API 24), cible Android 16 (API 36, exigée par Google Play depuis le 31/08/2026)

## Ce que fait l'application

**Passager** : carte et position, recherche d'adresse ou choix sur la carte, estimation par service,
commande (pour soi ou pour un proche), envoi de colis, suivi en direct (chauffeur sur la carte, code à
donner, appel, relance, annulation, partage du suivi), notation et reçu, historique filtrable avec recherche
instantanée, portefeuille et rechargement ChapChap Pay (page de paiement ouverte dans l'application, puis
vérification automatique), compte (modification, mot de passe, suppression).

**Chauffeur** : dossier (profil → pièces → engin → vérification) avec envoi de photos ou de PDF,
interrupteur en ligne, position GPS envoyée toutes les 8 s, demandes entrantes avec sonnerie en boucle et
compte à rebours, course en cours (arrivé, démarrage par code, fin, code de livraison, itinéraire Google Maps,
relance, relâche), notation du passager, gains.

**Guidage GPS intégré** (chauffeur) : navigation tour par tour dans l'application, avec la voix, sans Google Maps (bouton « Guidage vers le client / la destination »).

**Urgence** : bouton rouge pour le client et le chauffeur ; l'équipe Yawi est alertée avec la position en direct.

**Notifications** : Firebase Cloud Messaging. Canal « Courses et alertes » avec la sonnerie Yawi (audible
même application fermée), canal « Informations » avec le bip Yawi. Toucher une notification ouvre la course.

Les écrans de saisie riches (dossier chauffeur, support, reçus) sont les pages du site, ouvertes déjà
connectées grâce à un lien à usage unique fourni par l'API (`POST /api/v1/auth/web-link` → `/app/session`).

## Points d'API utilisés

Toutes les routes sont sous `{YAWI_URL}/api/v1`, avec l'en-tête `Authorization: Bearer {jeton}` sauf les routes publiques.

| Groupe | Routes |
|---|---|
| Public | `POST auth/login`, `POST auth/register`, `GET config`, `GET geo/search`, `geo/reverse`, `geo/route` |
| Compte | `GET me`, `POST auth/logout`, `POST auth/web-link`, `PUT profile`, `PUT profile/password`, `DELETE profile`, `POST/DELETE devices` |
| Passager | `GET home`, `POST estimate`, `GET/POST rides`, `POST deliveries`, `GET rides/{ref}`, `POST rides/{ref}/cancel·rate·nudge·nudge/ack`, `GET wallet`, `POST wallet/topup`, `GET payments/{ref}` |
| Chauffeur | `GET driver/onboarding`, `GET driver/feed`, `POST driver/online`, `POST driver/location`, `GET driver/earnings`, `POST driver/rides/{ref}/accept·decline·arrived·start·complete·cancel·rate·nudge·nudge/ack` |

Le détail (règles, réponses) est dans le README du projet Laravel, section « API v1 ».

## Organisation

```
yawi-app/
  .github/workflows/android.yml   build APK + AAB dans le cloud
  lib/
    core/        API (dio), session et jeton, charte, sonnerie et notifications, GPS
    widgets/     composants communs, carte OpenStreetMap
    screens/     auth, passenger, driver, account, common (WebView, recherche d'adresse)
  assets/        logo, polices Instrument Sans et Boldonse (OFL), sonnerie
  tool/
    prepare_android.py   génère et configure le projet Android
    android/res/         icônes, écran de lancement, sonnerie de notification
```

Le dossier `android/` n'est pas versionné au départ : il est **généré par la version de Flutter installée**
(fichiers Gradle toujours compatibles), puis configuré par `tool/prepare_android.py` (identifiant, SDK,
signature, Firebase, permissions, icônes). Le script peut être relancé sans risque.

## Construire l'APK et l'AAB

### Option A — dans le cloud (GitHub Actions, rien à installer)

1. Créez un dépôt GitHub pour ce projet (distinct de celui du site) et poussez-y ce dossier.
   Le workflow `.github/workflows/android.yml` se lance à chaque envoi sur `main`
   (ou à la main : onglet **Actions → Android → Run workflow**).
2. À la fin, téléchargez l'artefact `yawi-android-N` : `app-release.apk` (installation directe sur un
   téléphone) et `app-release.aab` (à envoyer sur Google Play).

Sans secrets, le build est signé avec une clé de debug : installable pour tester, refusé par Google Play.

### Option B — sur votre ordinateur

Prérequis : Flutter (stable, 3.35 ou plus), Android Studio (SDK Android), JDK 17, Python 3.

```bash
cd yawi-app
python3 tool/prepare_android.py      # crée android/ puis applique la configuration Yawi
flutter pub get
flutter run                          # téléphone branché en mode développeur
flutter build apk --release          # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release    # build/app/outputs/bundle/release/app-release.aab
```

Autre serveur (préproduction) : `--dart-define=YAWI_URL=https://staging.exemple.com`.

## Clé de signature (une seule fois, à conserver précieusement)

```bash
keytool -genkey -v -keystore yawi-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias yawi
base64 -w0 yawi-release.jks > yawi-release.jks.b64      # macOS : base64 -i yawi-release.jks
```

Sur GitHub (**Settings → Secrets and variables → Actions**), créez :

| Secret | Valeur |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | contenu de `yawi-release.jks.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | mot de passe du keystore |
| `ANDROID_KEY_ALIAS` | `yawi` |
| `ANDROID_KEY_PASSWORD` | mot de passe de la clé |

En local, placez `yawi-release.jks` dans `android/app/` et créez `android/key.properties` :

```
storeFile=yawi-release.jks
storePassword=…
keyAlias=yawi
keyPassword=…
```

Ces fichiers sont ignorés par Git. **Perdre le keystore empêche toute mise à jour sur Google Play** :
gardez-en une copie hors du dépôt (et activez la signature d'application Google Play).

## Notifications push (Firebase)

1. Console Firebase → projet Yawi → **Ajouter une application Android** avec le package `gn.yawi.app`.
2. Téléchargez `google-services.json` :
   - en local : copiez-le dans `android/app/` puis relancez `python3 tool/prepare_android.py` ;
   - sur GitHub : collez son contenu dans le secret `GOOGLE_SERVICES_JSON`.
3. Côté site : **Admin → Paramètres → Notifications push**, collez la clé de compte de service Firebase
   (déjà prévu pour l'application Capacitor : rien ne change).

Sans `google-services.json`, l'application fonctionne normalement mais sans notifications push
(les écrans se mettent à jour par actualisation toutes les 4 secondes lorsqu'ils sont ouverts).

## Côté serveur, projet Laravel (à faire une fois)

```bash
composer install --no-dev --optimize-autoloader   # installe laravel/sanctum
php artisan migrate --force                        # table personal_access_tokens
php artisan optimize:clear
```

Vérification rapide : `https://yawi.elitegroupe-sarl.com/api/v1/config` doit renvoyer du JSON.

## Publier sur Google Play

1. Play Console → **Créer une application** (Yawi, gratuite, catégorie Voyages et infos locales).
2. Fiche : textes et visuels de `store/` (fiche déjà rédigée,
   reprise de la version précédente), icône 512 px : `assets/images/icon-1024.png` redimensionnée.
3. **Contenu de l'application** : politique de confidentialité `…/confidentialite`, suppression de compte
   `…/supprimer-mon-compte`, sécurité des données (localisation précise, téléphone, nom ; chiffrées en transit).
4. **Localisation** : l'application n'utilise la position qu'au premier plan (pas de localisation en arrière-plan),
   ce qui évite la déclaration spéciale.
5. Envoyez `app-release.aab` en **test interne**, puis test fermé (12 testeurs pendant 14 jours pour un
   compte personnel récent), puis production.

## Version iOS (iPhone)

Une application iOS se compile **uniquement sur un Mac avec Xcode 26 ou plus** (exigence d'Apple pour App Store Connect
depuis le 28/04/2026). Rien n'est à installer sur votre ordinateur : un Mac dans le cloud fait le travail.

Le dossier `ios/` est généré par Flutter puis configuré par `tool/prepare_ios.py` (comme pour Android) :
identifiant `gn.yawi.app`, iPhone uniquement, portrait, iOS 15 minimum, icône et écran de lancement Yawi,
textes des autorisations en français, sonneries Yawi des notifications, capacité Push, Firebase.

### 1. Compte Apple Developer (99 $/an)

developer.apple.com/programs → inscription en **Organisation** (Elite Groupe SARL). Le même numéro **D-U-N-S**
que pour Google Play est demandé.

### 2. Identifiant de l'app et notifications

1. developer.apple.com → Certificates, IDs & Profiles → **Identifiers** → `+` → App IDs → App :
   Bundle ID `gn.yawi.app` (explicite), cocher **Push Notifications**.
2. **Keys** → `+` → cocher *Apple Push Notifications service (APNs)* → télécharger le fichier `.p8`
   (une seule fois) et noter le Key ID et le Team ID.
3. Console Firebase → projet `yawi-27cde` → **Ajouter une application iOS** (`gn.yawi.app`) → télécharger
   `GoogleService-Info.plist`. Puis Paramètres du projet → Cloud Messaging → *Configuration de l'app Apple* →
   envoyer la clé APNs `.p8` avec son Key ID et le Team ID.
4. Côté serveur, rien à changer : la clé de compte de service Firebase sert aussi pour iOS.

### 3. Fiche App Store Connect et clé API

1. appstoreconnect.apple.com → **Apps** → `+` → Nouvelle app : iOS, nom « Yawi », langue Français,
   Bundle ID `gn.yawi.app`, SKU `yawi-ios`.
2. **Utilisateurs et accès → Intégrations → Clés API App Store Connect** → générer une clé (accès *App Manager*) :
   noter l'**Issuer ID**, le **Key ID**, télécharger `AuthKey_XXXX.p8`.
3. Clé privée du certificat de distribution (une fois, à conserver avec la clé Android) :
   `ssh-keygen -t rsa -b 2048 -m PEM -f yawi_ios_cert_key -q -N ""`

### 4. Compiler

**GitHub Actions** (workflow `.github/workflows/ios.yml`, Mac `macos-26`) — secrets à créer :

| Secret | Valeur |
|---|---|
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Key ID de la clé API |
| `APP_STORE_CONNECT_PRIVATE_KEY` | contenu de `AuthKey_XXXX.p8` |
| `CERTIFICATE_PRIVATE_KEY` | contenu de `yawi_ios_cert_key` |
| `GOOGLE_SERVICE_INFO_PLIST` | contenu de `GoogleService-Info.plist` |

Variable `UPLOAD_TESTFLIGHT` = `true` pour envoyer chaque build sur TestFlight. Sans les secrets, le workflow
fait une compilation de contrôle non signée. Le certificat et le profil de distribution sont créés automatiquement.
Attention : les minutes macOS des dépôts **privés** sont décomptées 10 fois plus vite que Linux.

**Codemagic** (alternative, 500 minutes macOS gratuites par mois) : connecter le dépôt, ajouter la clé API
App Store Connect sous le nom `yawi-asc`, le groupe de variables `yawi` avec `GOOGLE_SERVICE_INFO_PLIST`,
puis lancer le workflow `ios-release` de `codemagic.yaml`.

**Sur un Mac** (Xcode 26) :

```bash
python3 tool/prepare_ios.py
cp ~/Téléchargements/GoogleService-Info.plist ios/Runner/ && python3 tool/prepare_ios.py --no-create
flutter run                 # iPhone branché ou simulateur
open ios/Runner.xcworkspace # Signing & Capabilities : choisir l'équipe, puis Product › Archive
```

### 5. Publier

TestFlight (testeurs internes immédiatement, externes après une courte vérification), puis dans App Store Connect :
captures iPhone 6,9 pouces (1320 × 2868), description, mots-clés, URL de support, politique de confidentialité
`…/confidentialite`, **confidentialité de l'app** (localisation précise, nom, téléphone, photos ; aucun suivi publicitaire),
classification par âge, **compte de démonstration** passager et chauffeur pour la vérification Apple, puis
« Soumettre pour vérification ». Apple exige aussi la suppression du compte dans l'app (déjà présente).

## Limites connues de cette première version

- Le chauffeur doit garder l'application ouverte pour que sa position soit envoyée (pas de service de
  localisation en arrière-plan) ; les nouvelles demandes arrivent quand même par notification.
- La réinitialisation du mot de passe passe par le support (pas encore de parcours automatique sur le site).
