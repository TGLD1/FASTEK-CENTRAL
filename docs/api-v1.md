# FASTEK CENTRAL — Contrat API v1

Statut : première spécification
Protocole : HTTPS
Format : REST + JSON
Préfixe : `/api/v1`

## 1. Principes

- Toutes les dates sont au format ISO 8601 UTC.
- Les identifiants d'installation sont générés aléatoirement par le SDK.
- L'identifiant public de l'application n'est pas un secret.
- Aucun secret administrateur ou clé privilégiée ne doit être envoyé par le client.
- Chaque installation appartient à une seule application.
- Une installation Notea ne peut accéder aux ressources de Cleaner, et inversement.
- Les erreurs utilisent un format commun.
- Les applications gratuites doivent continuer à fonctionner si CENTRAL est indisponible.

## 2. Enveloppe des réponses

Succès :

    {
      "data": {},
      "meta": {
        "request_id": "identifiant-de-requete"
      }
    }

Erreur :

    {
      "error": {
        "code": "ERROR_CODE",
        "message": "Description compréhensible",
        "details": {}
      },
      "meta": {
        "request_id": "identifiant-de-requete"
      }
    }

Le serveur génère le `request_id`. Il ne faut jamais y placer un secret.

## 3. Routes de la première tranche

### POST /api/v1/installations/register

Enregistre une installation d'une application approuvée.

Authentification : aucune pour cette route. L'identité de l'application
et les informations fournies doivent être vérifiées côté serveur.

Corps :
- `app_id` : identifiant permanent de l'application.
- `installation_id` : UUID généré et conservé par le SDK.
- `platform` : android, python ou javascript.
- `app_version` : version de l'application.
- `sdk_version` : version du SDK.
- `os_version` : version du système, facultative.
- `device_model` : modèle de l'appareil, facultatif.
- `capabilities` : capacités demandées par le SDK.

Réponse 201 :
- identifiant d'installation ;
- identifiant de session ;
- jeton d'accès ;
- jeton de renouvellement ;
- durées de validité en secondes ;
- capacités autorisées.

Règles :
- l'application doit exister et être active ;
- les capacités non autorisées sont refusées ou exclues de la réponse ;
- une installation possédant déjà une session active reçoit HTTP 409 ;
- aucune session existante n'est remplacée silencieusement.

### POST /api/v1/installations/token/refresh

Renouvelle une paire de jetons.

Authentification : jeton de renouvellement dans le corps.

En-tête obligatoire : `Idempotency-Key`, valeur aléatoire unique par
opération de renouvellement.

Corps :
- `refresh_token`.

Réponse 200 : nouvelle paire de jetons et durées de validité.

Règles :
- jeton d'accès : 1 heure ;
- jeton de renouvellement : 30 jours glissants ;
- rotation du jeton de renouvellement à chaque renouvellement réussi ;
- répétition avec la même clé dans les 5 minutes : restitution exacte
  de la réponse initiale ;
- réutilisation avec une clé différente ou après cette fenêtre :
  révocation de la session selon la politique anti-rejeu ;
- un jeton expiré qui n'a jamais été remplacé est simplement refusé ;
- le serveur ne stocke jamais les jetons en clair.

### POST /api/v1/installations/session/revoke

Révoque la session de l'installation qui effectue l'appel.

Authentification : Bearer access token.

Réponse 200 : confirmation de révocation.

Une installation ne peut pas révoquer la session d'une autre installation.

### GET /api/v1/installations/me

Retourne les informations techniques de l'installation authentifiée.

Authentification : Bearer access token.

Réponse 200 : identifiants, application associée, plateforme, statut,
versions et capacités autorisées.

Aucun contenu privé de l'application n'est retourné.

### POST /api/v1/installations/heartbeat

Signale une communication technique de l'installation.

Authentification : Bearer access token.

Corps : objet JSON vide `{}` dans cette première version.

Réponse 200 : date de dernière communication et statut de l'installation.

Un heartbeat technique ne signifie pas nécessairement qu'un utilisateur
est actif dans l'application.

## 4. Codes HTTP

- 200 : opération réussie.
- 201 : installation créée.
- 400 : requête invalide.
- 401 : jeton absent, invalide, expiré ou révoqué.
- 403 : application ou installation non autorisée/suspendue.
- 404 : ressource inconnue.
- 409 : conflit d'état ou session déjà active.
- 422 : données valides au format mais refusées par les règles métier.
- 429 : limite de débit atteinte.
- 500 : erreur interne.
- 503 : service temporairement indisponible.

## 5. En-têtes

- `Content-Type: application/json` pour les requêtes avec corps.
- `Authorization: Bearer <access_token>` pour les routes protégées.
- `Idempotency-Key` obligatoire pour le renouvellement.
- `X-Request-ID` peut être fourni par le client pour faciliter la
  corrélation ; le serveur reste responsable de l'identifiant final.

## 6. Hors périmètre de cette tranche

Commandes, notifications, configurations distantes, mises à jour,
licences, administration et statistiques avancées seront spécifiées
dans leurs modules respectifs.

## 7. État d'implémentation

Ce document et `openapi.yaml` définissent le contrat. Leur présence
ne signifie pas que les routes serveur sont déjà implémentées.
