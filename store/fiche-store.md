# Fiches des stores : Yawi

## Identité

| Champ | Valeur |
|---|---|
| Nom de l'application | Yawi |
| Sous-titre (App Store, 30 car. max) | Course, moto et colis à Conakry |
| Catégorie | Voyages (Play : Cartes et navigation ou Voyages et infos locales) |
| Identifiant | gn.yawi.app |
| Langue principale | Français |
| Prix | Gratuit |
| Public | 18 ans et plus (le service s'adresse à des adultes ; comptes chauffeurs majeurs uniquement) |
| Site | https://yawi.elitegroupe-sarl.com |
| Confidentialité | https://yawi.elitegroupe-sarl.com/confidentialite |
| Conditions | https://yawi.elitegroupe-sarl.com/conditions |
| Suppression du compte | https://yawi.elitegroupe-sarl.com/supprimer-mon-compte |
| E-mail de contact | (celui saisi dans Réglages › Coordonnées) |

## Description courte (Google Play, 80 caractères max)

Commandez une moto, un tricycle ou une voiture et envoyez vos colis à Conakry.

## Description complète

Yawi vous emmène partout à Conakry, au bon prix et sans négocier.

Commandez en quelques secondes
• Moto, tricycle, voiture économique, confort, XL ou premium.
• Le prix exact s'affiche avant de commander : il ne change pas pendant le trajet.
• Suivez votre chauffeur en direct sur la carte et recevez une alerte dès qu'il arrive.

Envoyez vos colis
• Indiquez le lieu de collecte et le destinataire, le livreur s'occupe du reste.
• Code de collecte et code de livraison : le colis n'est remis qu'à la bonne personne.
• Le destinataire suit la livraison par un simple lien, sans installer l'application.

Payez comme vous voulez
• En espèces au chauffeur, ou avec votre portefeuille Yawi.
• Rechargez par Orange Money, MTN MoMo, PayCard ou carte bancaire.
• Reçu disponible pour chaque course.

Voyagez en confiance
• Chauffeurs vérifiés : pièce d'identité, permis, certificat de résidence et documents de l'engin contrôlés.
• Code de démarrage à donner au chauffeur, notation après chaque course.
• Commandez pour un proche : il reçoit les infos du chauffeur et le lien de suivi.

Vous êtes chauffeur ?
Inscrivez-vous dans l'application, envoyez vos pièces et votre engin, et recevez des courses près de vous dès la validation de votre dossier.

## Mots-clés (App Store, 100 caractères max)

taxi,moto,vtc,conakry,guinée,course,colis,livraison,chauffeur,orange money,momo,transport

## Notes pour la vérification Apple (App Review Information)

Yawi is a ride-hailing and parcel delivery service in Conakry, Guinea. The app provides native features on top of our service:
- push notifications (Firebase) for ride requests, driver arrival, nudges, deliveries and payments;
- native GPS location (Capacitor Geolocation) to set the pickup point and track the driver;
- haptic feedback and an alert ringtone when the driver arrives or a ride request comes in;
- screen kept awake for drivers who are online;
- offline screen with automatic retry.

Wallet top-ups (Orange Money, MTN MoMo, cards via ChapChap Pay) pay for physical transport and delivery services consumed outside the app (guideline 3.1.3(e)).
Third-party sign-in is not offered in the iOS app (phone number and password only).
Account deletion: Account tab › « Supprimer mon compte ».

Demo accounts (password: à renseigner):
- Passenger: <e-mail ou téléphone de démonstration>
- Driver (already approved): <e-mail ou téléphone de démonstration>

## Sécurité des données (Google Play) et confidentialité (App Store)

Aucune donnée n'est vendue ni utilisée pour de la publicité. Toutes les données sont chiffrées en transit (HTTPS). L'utilisateur peut demander leur suppression.

| Donnée | Collectée | Usage | Liée à l'identité |
|---|---|---|---|
| Nom | Oui | Fonctionnement du compte | Oui |
| Numéro de téléphone | Oui | Compte, contact chauffeur / client | Oui |
| Adresse e-mail | Facultative | Compte | Oui |
| Position précise | Oui (app ouverte seulement) | Départ, chauffeurs proches, suivi | Oui |
| Historique de courses, adresses | Oui | Fonctionnement, reçus | Oui |
| Informations de paiement | Montants et références uniquement (pas de numéro de carte) | Paiement, comptabilité | Oui |
| Photos (chauffeurs) | Oui | Vérification du chauffeur, photo de profil | Oui |
| Pièces d'identité (chauffeurs) | Oui | Vérification du chauffeur | Oui |
| Identifiants d'appareil (jeton de notification) | Oui | Notifications | Oui |
| Diagnostics / analyses | Non | — | — |

Partage avec des tiers (prestataires) : ChapChap Pay (paiements), Google Firebase (notifications), hébergeur, OpenStreetMap (cartes). Le client et le chauffeur voient les informations utiles à la course.

## Visuels à préparer

- Icône 512×512 (Play) : `assets/icon-only.png` réduite. L'icône App Store (1024) est générée par `npm run icones`.
- Image de présentation Play 1024×500 : logo blanc sur fond #1B2735 avec une capture de l'écran Commander.
- Captures d'écran (au moins 2 sur Play, 3 conseillées sur l'App Store) : Commander (carte + services), suivi du chauffeur (bandeau coloré), livraison de colis, portefeuille (rechargement), dossier chauffeur.
