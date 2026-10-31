# FASTEK-CENTRAL

**Backend, API, logique serveur et migrations PostgreSQL de FASTEK CENTRAL.**

## Statut
Phase 1 — Fondations (en cours)

## Architecture retenue
- Supabase / PostgreSQL (base + auth)
- Supabase Edge Functions (API REST)
- Cloudflare Pages (admin)
- Cloudflare R2 (sauvegardes)
- GitHub Actions (CI/CD)

## Environnements
- `develop` → développement
- `staging` → validation
- `main` → production (déploiement uniquement après approbation du propriétaire)

## Règles importantes
- Aucun secret dans le code source
- Isolation stricte entre applications
- Notea reste offline-first et gratuit
- Travail progressif uniquement

## Documentation
Voir le dépôt `FASTEK-DOCUMENTATION`.

---
© FASTEK — Tous droits réservés
