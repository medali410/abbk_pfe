# Backend Node.js + PostgreSQL

Le backend est dans **`backend/`** (Prisma + Express). Guide local + partagé : **[POSTGRES_LOCAL_ET_PARTAGE.md](./POSTGRES_LOCAL_ET_PARTAGE.md)**.

Le frontend Flutter reste dans **`dali-pfe/`**.

## Stack recommandée (Flutter + Node + SQL)

| Couche | Choix courant |
|--------|----------------|
| Base | **PostgreSQL** (ou MySQL / MariaDB) |
| ORM | **Prisma** ou **Sequelize** |
| API | **Express** (ou Fastify) sur le port **3001** |
| Auth | JWT (comme avant) + bcrypt pour les mots de passe |

## Schéma SQL (équivalent de l’ancien Mongo)

```text
users           (id, nom, email, password_hash, adresse, role)
admins          (id, user_id FK)
clients         (id, user_id FK, client_id, location, …)
concepteurs     (id, user_id FK, specialite, …)
technicians     (id, user_id FK, company_id, …)
maintenance_agents (id, user_id FK, client_id, …)
machines        (id, name, company_id, status, …)
modeles_3d      (id, machine_id FK, name, photo_url, …)
telemetries     (id, machine_id, …)
```

Une ligne dans `users` + une ligne dans la table du rôle (même logique qu’avant).

## Flutter

`dali-pfe/lib/services/api_service.dart` appelle `http://localhost:3001/api/...`.

Quand le nouveau backend SQL sera prêt :

- Garder les mêmes routes si possible (`/api/login`, `/api/clients`, `/api/machines`, …)
- Ou adapter `api_service.dart` une fois l’OpenAPI / la doc des nouvelles routes fixée.

## Démarrer seulement le frontend

```powershell
cd dali-pfe
flutter run -d chrome --dart-define=API_PORT=3001
```

Sans backend, l’app affichera des erreurs réseau jusqu’à ce que l’API SQL soit en place.

## Prochaine étape (à coder)

1. Créer un dossier `backend/` (Express + Prisma + PostgreSQL).
2. Définir le schéma Prisma (`schema.prisma`).
3. Réimplémenter login + CRUD clients / machines / modèles 3D.
4. Brancher Flutter sur les mêmes endpoints.
