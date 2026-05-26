# DALI PFE — Frontend Flutter

Application Flutter (`dali-pfe`). L’ancien backend MongoDB (`iot-backend`) a été retiré.

## Lancer l’app (sans API pour l’instant)

```powershell
cd dali-pfe
flutter pub get
flutter run -d chrome --dart-define=API_PORT=3001
```

Les appels HTTP dans `lib/services/api_service.dart` ciblent `http://localhost:3001/api` — un **nouveau backend Node.js + SQL** doit être ajouté (voir `../docs/BACKEND_SQL.md` à la racine du dépôt).

## Documentation

- Plan backend SQL : `../docs/BACKEND_SQL.md`
