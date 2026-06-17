// ================================================================
// ABBK Backend — src/lib/aiPredictionService.js
// ================================================================

const axios = require('axios');
const { prisma } = require('./prisma');

const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8001';

async function predictMachineRisk(machineId, telemetry) {
  try {
    const courant   = parseFloat(telemetry.courant   || telemetry.current)  || 0;
    const puissance = parseFloat(telemetry.puissance || telemetry.power)    || 0;
    const voltage   = parseFloat(telemetry.voltage   || telemetry.tension)  || 0.0;
    const pressure  = parseFloat(telemetry.pression  || telemetry.pressure) || null;
    const temp_contact = parseFloat(
      telemetry.temperature_contact || telemetry.temperature ||
      telemetry.thermal || telemetry.temp
    ) || 0;
    const temp_infra = parseFloat(
      telemetry.temperature_infrarouge || telemetry.infrared || temp_contact
    ) || 0;

    // ── Conversion vibration : Flutter envoie en mm/s, Python attend en g ──────
    // ADXL345 brut (MQTT direct) → vibration_x/vibration_y déjà en g
    // Flutter (depuis BDD)       → champ "vibration" déjà en mm/s
    let vib_x, vib_y;
    if (telemetry.vibration_x !== undefined && telemetry.vibration_x !== null) {
      // Données MQTT brutes : déjà en g
      vib_x = parseFloat(telemetry.vibration_x) || 0;
      vib_y = parseFloat(telemetry.vibration_y  || telemetry.vibration_x * 0.8) || 0;
    } else {
      // Flutter envoie "vibration" en mm/s → convertir en g (1 g ≈ 50 mm/s)
      const vib_mms = parseFloat(telemetry.vibration) || 0;
      vib_x = vib_mms / 50.0;   // ex: 29.41 mm/s → 0.588 g
      vib_y = vib_x * 0.8;
    }
    // ─────────────────────────────────────────────────────────────────────────────

    // Vibration réelle en mm/s pour les overrides capteurs
    const vib_mms_total = Math.sqrt(vib_x * vib_x + vib_y * vib_y) * 50;

    // GUARD: Si la machine est manifestement à l'arrêt
    if (puissance === 0 && courant === 0 && vib_x === 0 && vib_y === 0) {
      return {
        machine_id:      machineId,
        status:          'Normal',
        risk_percentage: 0,
        type_panne:      'ARRÊT',
        diagnostic:      'Machine actuellement à l\'arrêt ou en veille.',
        recommandation:  'Aucune action requise. En attente de démarrage.',
        urgence:         'faible',
        details: {
          panne_probability: 0.0,
          anomalie_probability: 0.0,
          rul_cycles: 0,
          scenario_scores: { 'NORMAL': 1.0 }
        }
      };
    }

    // Fetch machine to get its aiType if not present in telemetry
    let machine_type = telemetry.machine_type;
    if (!machine_type) {
      const machine = await prisma.machine.findFirst({
        where: machineId.length === 24 ? { id: String(machineId) } : { name: String(machineId) }
      });
      machine_type = machine ? (machine.aiType || 'M') : 'M';
    }

    const payload = {
      machine_id:             machineId,
      temperature_contact:    temp_contact,
      temperature_infrarouge: temp_infra,
      vibration_x:            vib_x,
      vibration_y:            vib_y,
      courant:                courant,
      puissance:              puissance,
      pression:               pressure,
      tension:                voltage || 220.0,
      vibration_z:            vib_x * 0.5,
      frequence:              parseFloat(telemetry.frequency  || 50),
      machine_type:           machine_type,
      history:                telemetry.history || [],
    };

    const response = await axios.post(`${AI_SERVICE_URL}/predict`, payload, {
      timeout: 5000
    });

    let aiResult = response.data;

    // Override demandé : si le voltage est < 250V, on force le modèle à l'état Normal et risque 20%
    if (voltage > 0 && voltage < 250) {
      aiResult.type_panne = 'NORMAL';
      aiResult.status = 'Normal';
      aiResult.risk_percentage = 20;
      aiResult.diagnostic = '✅ Machine en bon état de fonctionnement.';
      aiResult.recommandation = 'Aucune action requise. Continuer la surveillance.';
      aiResult.urgence = 'faible';
      if (aiResult.details) {
         aiResult.details.anomalie_probability = 0.20;
         aiResult.details.scenario_scores = { 'NORMAL': 1.0 };
      }
    }

    // ── Override capteur : les seuils physiques priment sur le modèle ──────────
    const SENSOROVERRIDES = [
      {
        // Vibration danger : > 20 mm/s → ROULEMENT
        condition: vib_mms_total > 20 &&
                   aiResult.type_panne !== 'ROULEMENT',
        type_panne:    'ROULEMENT',
        diagnostic:    '🔧 Vibrations anormales — usure probable des roulements.',
        recommandation:"Planifier une inspection mécanique. Vérifier les roulements et l'alignement.",
        urgence:       'haute',
        status:        'Critical',
      },
      {
        // Surchauffe : temp > 50°C → SURCHAUFFE
        condition: temp_contact > 50 &&
                   aiResult.type_panne !== 'SURCHAUFFE',
        type_panne:    'SURCHAUFFE',
        diagnostic:    '🌡️ Température anormalement élevée détectée.',
        recommandation:'Vérifier le système de refroidissement. Réduire la charge si possible.',
        urgence:       'haute',
        status:        'Critical',
      },
    ];

    const override = SENSOROVERRIDES.find(o => o.condition);
    if (override) {
      console.log(`[AI Override] ${aiResult.type_panne} → ${override.type_panne} (vib=${vib_mms_total.toFixed(1)}mm/s, temp=${temp_contact}°C)`);
      aiResult = {
        ...aiResult,
        type_panne:    override.type_panne,
        diagnostic:    override.diagnostic,
        recommandation:override.recommandation,
        urgence:       override.urgence,
        status:        override.status,
        risk_percentage: Math.max(aiResult.risk_percentage, override.status === 'Critical' ? 70 : 45),
        details: {
          ...(aiResult.details || {}),
          sensor_override: true,
          override_reason: `Vibration=${vib_mms_total.toFixed(1)}mm/s, Temp=${temp_contact}°C`,
        }
      };
    }

    if (aiResult.details) {
      let courant_risk = 0;
      if (voltage > 250) courant_risk = 80 + Math.min(20, (voltage - 250));
      else if (voltage > 0) courant_risk = 10 + (voltage / 250) * 10;
      
      aiResult.details.scenario_scores = {
        "RISQUE TOTAL": aiResult.risk_percentage / 100.0,
        "VIBRATION": (aiResult.details.vibration_risk || 0) / 100.0,
        "TEMPÉRATURE": (aiResult.details.heat_risk || 0) / 100.0,
        "COURANT": Math.round(courant_risk) / 100.0
      };
    }

    return aiResult;

  } catch (error) {
    console.error('[AI Service] Erreur prédiction:', error.message);
    return {
      machine_id:      machineId,
      status:          'Unknown',
      risk_percentage: 0,
      type_panne:      'INCONNU',
      diagnostic:      'Service IA indisponible',
      recommandation:  'Vérifier que le service IA est démarré.',
      urgence:         'faible',
      details:         {}
    };
  }
}

async function handleAIPrediction(machineId, aiResult, io) {
  try {
    const machine = await prisma.machine.findFirst({
      where: machineId.length === 24 ? { id: machineId } : { name: machineId }
    });

    if (!machine) {
      console.warn(`[AI Service] Machine ${machineId} non trouvée dans la BDD. Enregistrement ignoré.`);
      return;
    }

    if (aiResult.status !== 'Unknown') {
      await prisma.prediction.create({
        data: {
          machineId:      machine.id,
          status:         aiResult.status,
          riskPercentage: aiResult.risk_percentage,
          typePanne:      aiResult.type_panne,
          diagnostic:     aiResult.diagnostic,
          recommandation: aiResult.recommandation,
          urgence:        aiResult.urgence,
          rulCycles:      aiResult.details?.rul_cycles ?? null,
          scenarioScores: JSON.stringify(aiResult.details?.scenario_scores ?? {}),
        }
      });
    }

    if (aiResult.status === 'Critical') {
      const agents = await prisma.maintenanceAgent.findMany({
        include: { user: true }
      });

      for (const agent of agents) {
        await prisma.notification.create({
          data: {
            userId: agent.userId,
            role:   'MAINTENANCE_AGENT',
            type:   'CRITICAL',
            title:  `⚠️ Risque critique — ${machine.name}`,
            body:   `${aiResult.diagnostic} | ${aiResult.recommandation}`,
            isRead: false,
          }
        });
      }

      if (io) {
        io.emit('machine:alert', {
          machineId:      machine.id,
          type:           'CRITICAL',
          riskPercentage: aiResult.risk_percentage,
          typePanne:      aiResult.type_panne,
          diagnostic:     aiResult.diagnostic,
          recommandation: aiResult.recommandation,
        });
        console.log(`🚨 Alerte critique émise pour machine ${machine.id}`);
      }
    }

    if (io) {
      io.emit(`ai:${machine.id}`, {
        machineId:      machine.id,
        status:         aiResult.status,
        riskPercentage: aiResult.risk_percentage,
        typePanne:      aiResult.type_panne,
        diagnostic:     aiResult.diagnostic,
        recommandation: aiResult.recommandation,
        urgence:        aiResult.urgence,
        rulCycles:      aiResult.details?.rul_cycles,
        scenarioScores: aiResult.details?.scenario_scores,
        anomalieProbability: aiResult.details?.anomalie_probability,
      });
    }

  } catch (err) {
    console.error('[AI Service] Erreur handleAIPrediction:', err.message);
  }
}

module.exports = { predictMachineRisk, handleAIPrediction };
