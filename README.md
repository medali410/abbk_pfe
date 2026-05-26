# ABBK PFE

| Dossier | Rôle |
|---------|------|
| **`dali-pfe/`** | Application **Flutter** (frontend) — conservée |
| **`backend/`** | API **Node.js + SQL** (Prisma, port 3001) |
| **`docs/ARCHITECTURE_MVC.md`** | Structure MVC (backend + Flutter) |
| **`docs/POSTGRES_LOCAL_ET_PARTAGE.md`** | PostgreSQL local + base Neon/Supabase avec collègue |
| `modele_moteur_ia_inspect/` | Entraînement modèles ML (optionnel, hors API) |

Le dossier **`iot-backend/`** (MongoDB / Express) a été **supprimé** pour repartir sur une base SQL.

## Démarrer le frontend

```powershell
cd dali-pfe
flutter run -d chrome --dart-define=API_PORT=3001
```
