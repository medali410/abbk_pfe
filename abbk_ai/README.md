# ABBK AI — Module Prédiction de Panne

## Modèle utilisé
**`jskswamy/predictive-maintenance-model`** — HuggingFace
- Algorithme : AdaBoost (383 estimateurs)
- Recall : 99.78%
- Licence : MIT

## Installation
```bash
pip install -r requirements.txt
```

## Lancer le service
```bash
uvicorn app.main:app --reload --port 8001
```

## Tester
```bash
python test_service.py
```

## Endpoint principal
`POST /predict`

```json
{
  "machine_id": "MAC_VERIN_001",
  "temperature_contact": 45.2,
  "temperature_infrarouge": 48.7,
  "vibration_x": 0.12,
  "vibration_y": 0.08,
  "courant": 3.5,
  "puissance": 750.0
}
```

## Mapping capteurs
- DS18B20        → `temperature_contact`
- MLX90614       → `temperature_infrarouge`
- ADXL345 X      → `vibration_x`
- ADXL345 Y      → `vibration_y`
- PZEM courant   → `courant`
- PZEM puissance → `puissance`

## Seuils
- 0%  – 39%  → **Normal**
- 40% – 69%  → **Warning**
- 70% – 100% → **Critical**

## Intégration Node.js
```javascript
const { handleTelemetryWithAI } = require('./aiPredictionService');

mqttClient.on('message', async (topic, message) => {
  const telemetry = JSON.parse(message.toString());
  const machineId = topic.split('/')[1];
  await handleTelemetryWithAI(machineId, telemetry, io, prisma);
});
```

## Variable d'environnement
`AI_SERVICE_URL=http://localhost:8001`
