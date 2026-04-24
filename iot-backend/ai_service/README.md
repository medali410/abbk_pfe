# DALI IA Inference Service

Service Python FastAPI qui expose le modele de maintenance predictive.

## 1) Installer les dependances

```bash
python -m pip install -r "iot-backend/ai_service/requirements.txt"
```

## 2) Mode tabulaire (XGBoost + Isolation Forest, dataset AI4I)

1. Télécharger `ai4i2020.csv` (ex. [UCI](https://archive.ics.uci.edu/ml/machine-learning-databases/00601/ai4i2020.csv)) et le placer sous `iot-backend/ai4i2020.csv` ou passer `--csv` au script.
2. Entraîner les artefacts :

```bash
cd <racine_du_repo>
python modele_moteur_ia_inspect/train_tabular.py --csv iot-backend/ai4i2020.csv
```

Après chaque ré-entraînement, régénérer les exemples pour `POST /api/predict` :

```bash
python modele_moteur_ia_inspect/pick_predict_examples.py
```

(cible par défaut `iot-backend/examples_predict_tabular.json`.)

3. Lancer l’inférence en mode tabulaire (sans charger le LSTM) :

```powershell
$env:USE_TABULAR="1"
cd "iot-backend/ai_service"
uvicorn inference_api:app --host 0.0.0.0 --port 5000
```

Variables : `USE_TABULAR=1`, optionnel `TABULAR_ARTIFACTS_DIR` (défaut : `modele_moteur_ia_inspect/models_tabular`).

## 3) Variables optionnelles (LSTM)

- `MODEL_ARTIFACTS_DIR`: dossier contenant:
  - `best_model_v2.keras`
  - `scaler.pkl`
  - `le_type.pkl`
  - `le_scenario.pkl`
  - `metadata.json`
- `ML_SERVER`: deja lu cote Node (`http://localhost:5000` par defaut)

Exemple PowerShell:

```powershell
$env:MODEL_ARTIFACTS_DIR="C:\Users\ASUS\Desktop\dali_pfe\modele_moteur_ia_inspect\models_v2_step4"
```

## 4) Demarrer le service IA (LSTM par défaut)

```bash
cd "iot-backend/ai_service"
uvicorn inference_api:app --host 0.0.0.0 --port 5000
```

## 5) Demarrer le backend Node

```bash
npm start
```

## 6) Tester prediction

POST `http://localhost:3001/api/predict`

```json
{
  "machineId": "MAC_A01",
  "type_moteur": "EL_M",
  "temperature": 58.2,
  "pressure": 120,
  "power": 4200,
  "vibration": 2.1,
  "presence": 1,
  "magnetic": 0.7,
  "infrared": 62.5,
  "rpm": 1750,
  "torque": 45,
  "tool_wear": 95
}
```

La reponse inclut `prediction`, `prob_panne`, `niveau`, `panne_type`, `rul_estime`.
