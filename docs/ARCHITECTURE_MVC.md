# Architecture MVC — ABBK PFE

Le projet suit une **architecture MVC** (Model – View – Controller) sur le backend et, progressivement, sur Flutter.

## Backend (`backend/src/`)

```text
routes/          → URLs Express (couche routage, sans logique métier)
controllers/     → Controller : reçoit req/res, appelle Model, renvoie View
models/          → Model : accès données Prisma + règles métier (ex. dashboard)
views/           → View : format JSON pour le client (sérialisation)
lib/             → Infrastructure (prisma, auth JWT, googleAuth, ids)
```

| Fichier | Rôle MVC |
|---------|----------|
| `routes/*.js` | Point d’entrée HTTP → délègue au **Controller** |
| `controllers/*.js` | **Controller** |
| `models/*.js` | **Model** |
| `views/userView.js`, `views/machineView.js` | **View** (réponses API) |
| `lib/auth.js` | Middleware + helpers auth (pas la View) |

### Exemple de flux

`GET /api/dashboard/kpis` → `routes/dashboard.js` → `dashboardController.kpis` → `dashboardModel.getKpis()` → `res.json(...)`.

### Compatibilité

- `lib/serialize.js` et `lib/dashboardStats.js` réexportent les nouvelles couches (anciens imports inchangés).

## Flutter (`dali-pfe/lib/`)

```text
mvc/
  models/        → état / données (ex. dashboard_state.dart)
  controllers/   → logique, appels ApiService (ex. dashboard_controller.dart)
lib/
  *_page.dart    → View (widgets, navigation, pas de logique API lourde)
  services/      → accès réseau (couche données distante, utilisée par les Models/Controllers)
```

| Couche | Exemple |
|--------|---------|
| **Model** | `mvc/models/dashboard_state.dart` |
| **Controller** | `mvc/controllers/dashboard_controller.dart` (`ChangeNotifier`) |
| **View** | `dashboard_page.dart` (UI + `setState` via listener du controller) |

### Module pilote

Le **dashboard admin** est migré en MVC. Les autres écrans (`login_page`, `client_dashboard_page`, …) peuvent suivre le même schéma :

1. Créer `mvc/models/<feature>_state.dart`
2. Créer `mvc/controllers/<feature>_controller.dart`
3. Alléger la `*_page.dart` pour n’afficher que `_controller.state`

## Ce que ce n’est pas

- **Microservices** : un seul service API Node.
- **MVVM strict** : pas de binding déclaratif type Riverpod/Bloc (possible plus tard).

## Démarrage

Inchangé — voir `README.md` et `backend/README.md`.
