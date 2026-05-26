# Installation Windows — sans Docker

Si vous voyez `docker` ou `npm` **n'est pas reconnu**, suivez ce guide dans l’ordre.

---

## Étape 1 — Node.js (obligatoire)

1. Télécharger **LTS** : https://nodejs.org/ (bouton vert « LTS »).
2. Lancer l’installateur `.msi`.
3. Cocher **« Add to PATH »** (ajouter au PATH).
4. Terminer l’installation.
5. **Fermer** PowerShell / Cursor, puis **rouvrir** un terminal.

Vérification :

```powershell
node -v
npm -v
```

Vous devez voir des numéros de version (ex. `v22.x`, `10.x`).  
Si ça échoue encore : redémarrer le PC une fois.

---

## Étape 2 — Base Neon (recommandé)

Pas de PostgreSQL à installer sur le PC.

1. Compte gratuit : https://neon.tech → **New Project** → nom `dali_pfe`.
2. Onglet **Connection details** → copier l’URI **PostgreSQL** (avec mot de passe).
3. Dans `backend` :

```powershell
cd c:\Users\Administrator\OneDrive\Documents\abbk_pfe\backend
copy .env.example .env
notepad .env
```

4. Coller votre `DATABASE_URL` Neon à la place de l’exemple.
5. Choisir un `JWT_SECRET` (même texte pour la collègue si vous partagez la base).

```powershell
npm install
npm run setup
npm run dev
```

Test : http://localhost:3001/api/health

---

## Étape 3 — Flutter

```powershell
cd c:\Users\Administrator\OneDrive\Documents\abbk_pfe\dali-pfe
flutter run -d chrome --dart-define=API_PORT=3001
```

Connexion : `admin@dali-pfe.com` / `Admin2026!`

---

## Script automatique (après Node installé)

```powershell
cd c:\Users\Administrator\OneDrive\Documents\abbk_pfe\backend
powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1
```

---

## Résumé collègue (base partagée)

| Élément | Vous | Collègue |
|---------|------|----------|
| Code | `backend` + `dali-pfe` | même dépôt |
| `.env` | `DATABASE_URL` Neon | **identique** |
| `JWT_SECRET` | votre secret | **identique** |
| `npm run setup` | **une fois** (base vide) | non (déjà fait) |
| `npm run dev` | oui | oui |

---

## PostgreSQL local (optionnel, plus tard)

Même fichier `.env` : remplacer uniquement `DATABASE_URL`, par exemple :

```env
DATABASE_URL="postgresql://postgres:VOTRE_MOT_DE_PASSE@localhost:5432/dali_pfe?schema=public"
```

Avec Docker (`docker compose up -d`) :

```env
DATABASE_URL="postgresql://dali:dali_local_2026@localhost:5432/dali_pfe?schema=public"
```

Puis `npm run db:push` (ou `npm run setup` sur une base locale vide).

Détails : [`../docs/POSTGRES_LOCAL_ET_PARTAGE.md`](../docs/POSTGRES_LOCAL_ET_PARTAGE.md).
