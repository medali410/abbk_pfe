# PostgreSQL — un seul `.env`

Le backend utilise **un fichier** : `backend/.env` (modèle commité : `backend/.env.example`).

Par défaut : **Neon** (base cloud). Pour le dev local, on change seulement `DATABASE_URL` dans ce même fichier.

---

## 1. Neon — vous + collègue (recommandé)

### Créer la base (une fois)

1. Compte gratuit sur **[Neon](https://neon.tech)**.
2. Nouveau projet → base `dali_pfe`.
3. Copier la **connection string** PostgreSQL (avec mot de passe).

### Premier PC

```powershell
cd backend
copy .env.example .env
# Éditer .env : DATABASE_URL Neon + JWT_SECRET
npm install
npm run setup
npm run dev
```

`npm run setup` : tables + admin — **une fois** sur une base vide.

### Collègue

1. Même code `backend/` + `dali-pfe/`.
2. Recevoir en privé (pas Git) : `DATABASE_URL` et `JWT_SECRET` (identiques).
3. :

```powershell
cd backend
copy .env.example .env
# Coller les mêmes valeurs
npm install
npm run db:push
npm run dev
```

Pas de second `setup` si la base est déjà initialisée.

### Flutter (les deux)

```powershell
cd dali-pfe
flutter run -d chrome --dart-define=API_PORT=3001
```

Chacun lance son `npm run dev` (API locale port 3001) ; les deux API pointent vers **la même** base Neon.

---

## 2. PostgreSQL local (optionnel)

Éditer **le même** `backend/.env` et remplacer `DATABASE_URL` :

### Docker

```powershell
cd backend
docker compose up -d
```

```env
DATABASE_URL="postgresql://dali:dali_local_2026@localhost:5432/dali_pfe?schema=public"
```

### Windows (installateur EDB)

```sql
CREATE DATABASE dali_pfe;
```

```env
DATABASE_URL="postgresql://postgres:VOTRE_MDP@localhost:5432/dali_pfe?schema=public"
```

Puis :

```powershell
npm run db:push
```

(Les données ne sont pas copiées automatiquement entre local et Neon.)

---

## 3. Checklist collègue (Neon)

- [ ] Même `DATABASE_URL`
- [ ] Même `JWT_SECRET`
- [ ] `npm run dev` sur port 3001
- [ ] Flutter `--dart-define=API_PORT=3001`

---

## 4. Sécurité

- Ne jamais committer `.env` (déjà dans `.gitignore`).
- Ne pas exposer le mot de passe Neon en public.
- Changer `JWT_SECRET` en production.
