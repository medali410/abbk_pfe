# Backend DALI PFE — Node.js + PostgreSQL (Prisma)

API pour **Flutter** (`dali-pfe`), port **3001**. Architecture **MVC** : `src/controllers`, `src/models`, `src/views` (détail : [`../docs/ARCHITECTURE_MVC.md`](../docs/ARCHITECTURE_MVC.md)).

Un seul fichier d’environnement : **`.env`** (modèle : **`.env.example`** — Neon par défaut).

Guide détaillé : [`../docs/POSTGRES_LOCAL_ET_PARTAGE.md`](../docs/POSTGRES_LOCAL_ET_PARTAGE.md)

---

## Prérequis Windows

**Node.js** doit être installé : https://nodejs.org (LTS, cocher *Add to PATH*, redémarrer le terminal).

Si `npm` ou `docker` n’est pas reconnu → lire **`INSTALL_WINDOWS.md`**.

## Démarrage rapide (Neon)

```powershell
cd backend
copy .env.example .env
notepad .env
npm install
npm run setup
npm run dev
```

1. Créer un projet sur [Neon](https://neon.tech) → copier `DATABASE_URL`.
2. Coller l’URL dans `.env` + choisir un `JWT_SECRET` (partagé avec la collègue si besoin).
3. **Une fois** sur une base vide : `npm run setup`.
4. Collègue : même `.env` (URL + JWT), `npm run db:push`, `npm run dev`.

Health : http://localhost:3001/api/health

---

## Schéma SQL

- `users` → `admins`, `clients`, `concepteurs`, `technicians`, `maintenanceagents`
- `machines` ↔ `modeles_3d`

## Flutter

```powershell
cd dali-pfe
flutter run -d chrome --dart-define=API_PORT=3001
```

Login démo : **admin@dali-pfe.com** / **Admin2026!**

## Commandes

| Commande | Action |
|----------|--------|
| `npm run dev` | API |
| `npm run setup` | Tables + seed (base vide) |
| `npm run db:push` | Mettre à jour le schéma |
| `npm run db:local:up` | Docker PostgreSQL local (optionnel) |
| `npm run db:studio` | Prisma Studio |
