// ============================================================
// ABBK Backend — Integration Service IA (Python FastAPI)
// Fichier : services/aiPredictionService.js
// ============================================================

const axios = require('axios');

const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8001';

async function predictMachineRisk(machineId, telemetry) {
  try {
    const payload = {
      machine_id:             machineId,
      machine_type:           telemetry.machine_type   ?? 'M',
      temperature_contact:    telemetry.temp_ds18b20   ?? 0,
      temperature_infrarouge: telemetry.temp_mlx90614  ?? 0,
      vibration_x:            telemetry.accel_x        ?? 0,
      vibration_y:            telemetry.accel_y        ?? 0,
      courant:                telemetry.current        ?? 0,
      puissance:              telemetry.power          ?? 0,
      tension:                telemetry.voltage        ?? null,
      vibration_z:            telemetry.accel_z        ?? null,
      frequence:              telemetry.frequency      ?? null,
    };

    const response = await axios.post(`${AI_SERVICE_URL}/predict`, payload, {
      timeout: 5000
    });

    return response.data;

  } catch (error) {
    console.error('[AI Service] Erreur prédiction:', error.message);
    return {
      machine_id: machineId,
      risk_score: 0,
      risk_percentage: 0,
      status: 'Unknown',
      needs_maintenance: false,
      message: 'Service IA indisponible',
      details: {}
    };
  }
}


async function handleTelemetryWithAI(machineId, telemetryData, io, prisma) {

  // 1. Sauvegarder la télémétrie
  const savedTelemetry = await prisma.telemetry.create({
    data: {
      machineId,
      ...telemetryData,
      timestamp: new Date()
    }
  });

  // 2. Appel au service IA
  const aiResult = await predictMachineRisk(machineId, telemetryData);

  // 3. Sauvegarder la prédiction
  if (aiResult.status !== 'Unknown') {
    await prisma.prediction.create({
      data: {
        machineId,
        riskScore:        aiResult.risk_score,
        riskPercentage:   aiResult.risk_percentage,
        status:           aiResult.status,
        needsMaintenance: aiResult.needs_maintenance,
        message:          aiResult.message,
        anomalies:        aiResult.details.anomalies_detectees ?? [],
        timestamp:        new Date()
      }
    });
  }

  // 4. Alerte si critique
  if (aiResult.status === 'Critical') {
    await prisma.notification.create({
      data: {
        title:     `⚠️ Risque critique — Machine ${machineId}`,
        body:      aiResult.message,
        machineId,
        isRead:    false,
        createdAt: new Date()
      }
    });

    io.emit('machine:alert', {
      machineId,
      type:            'CRITICAL',
      riskPercentage:  aiResult.risk_percentage,
      message:         aiResult.message,
      anomalies:       aiResult.details.anomalies_detectees
    });
  }

  // 5. Push temps réel Flutter
  io.emit(`telemetry:${machineId}`, {
    ...telemetryData,
    ai: {
      risk_percentage:  aiResult.risk_percentage,
      status:           aiResult.status,
      needs_maintenance: aiResult.needs_maintenance
    }
  });

  return { telemetry: savedTelemetry, prediction: aiResult };
}


module.exports = {
  predictMachineRisk,
  handleTelemetryWithAI
};
