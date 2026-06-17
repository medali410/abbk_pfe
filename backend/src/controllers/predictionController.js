// ================================================================
// ABBK Backend — src/controllers/predictionController.js
// ================================================================

const prisma = require('../lib/prisma');

// ─── GET /api/machines/:machineId/predictions ───────────────────
async function getPredictions(req, res) {
  try {
    const { machineId } = req.params;
    const limit = parseInt(req.query.limit) || 20;
    const page  = parseInt(req.query.page)  || 1;
    const skip  = (page - 1) * limit;

    const machine = await prisma.machine.findUnique({
      where: { id: machineId }
    });
    if (!machine) {
      return res.status(404).json({ error: 'Machine introuvable' });
    }

    const [predictions, total] = await Promise.all([
      prisma.prediction.findMany({
        where:   { machineId },
        orderBy: { createdAt: 'desc' },
        take:    limit,
        skip,
      }),
      prisma.prediction.count({ where: { machineId } })
    ]);

    const parsed = predictions.map(p => ({
      ...p,
      scenarioScores: JSON.parse(p.scenarioScores || '{}')
    }));

    return res.json({
      machineId,
      machineName:  machine.name,
      total,
      page,
      limit,
      predictions:  parsed
    });

  } catch (err) {
    console.error('[predictionController] getPredictions:', err.message);
    return res.status(500).json({ error: err.message });
  }
}


// ─── GET /api/machines/:machineId/predictions/latest ───────────
async function getLatestPrediction(req, res) {
  try {
    const { machineId } = req.params;

    const prediction = await prisma.prediction.findFirst({
      where:   { machineId },
      orderBy: { createdAt: 'desc' }
    });

    if (!prediction) {
      return res.status(404).json({
        error: 'Aucune prédiction disponible pour cette machine'
      });
    }

    return res.json({
      ...prediction,
      scenarioScores: JSON.parse(prediction.scenarioScores || '{}')
    });

  } catch (err) {
    console.error('[predictionController] getLatestPrediction:', err.message);
    return res.status(500).json({ error: err.message });
  }
}


// ─── GET /api/predictions/critical ─────────────────────────────
async function getCriticalMachines(req, res) {
  try {
    const latest = await prisma.prediction.findMany({
      where:    { status: 'Critical' },
      orderBy:  { createdAt: 'desc' },
      distinct: ['machineId'],
    });

    const parsed = latest.map(p => ({
      ...p,
      scenarioScores: JSON.parse(p.scenarioScores || '{}')
    }));

    return res.json({
      total:    parsed.length,
      machines: parsed
    });

  } catch (err) {
    console.error('[predictionController] getCriticalMachines:', err.message);
    return res.status(500).json({ error: err.message });
  }
}


// ─── GET /api/machines/:machineId/predictions/stats ────────────
async function getPredictionStats(req, res) {
  try {
    const { machineId } = req.params;
    const hours = parseInt(req.query.hours) || 24;
    const since = new Date(Date.now() - hours * 60 * 60 * 1000);

    const predictions = await prisma.prediction.findMany({
      where: {
        machineId,
        createdAt: { gte: since }
      },
      orderBy: { createdAt: 'asc' },
      select: {
        createdAt:      true,
        riskPercentage: true,
        status:         true,
        typePanne:      true,
        rulCycles:      true,
      }
    });

    const statusCount = predictions.reduce((acc, p) => {
      acc[p.status] = (acc[p.status] || 0) + 1;
      return acc;
    }, {});

    const panneCount = predictions.reduce((acc, p) => {
      acc[p.typePanne] = (acc[p.typePanne] || 0) + 1;
      return acc;
    }, {});

    const avgRisk = predictions.length > 0
      ? Math.round(
          predictions.reduce((s, p) => s + p.riskPercentage, 0)
          / predictions.length
        )
      : 0;

    const lastRul = predictions.length > 0
      ? predictions[predictions.length - 1].rulCycles
      : null;

    return res.json({
      machineId,
      period_hours:  hours,
      total_records: predictions.length,
      avg_risk:      avgRisk,
      last_rul:      lastRul,
      status_count:  statusCount,
      panne_count:   panneCount,
      history:       predictions
    });

  } catch (err) {
    console.error('[predictionController] getPredictionStats:', err.message);
    return res.status(500).json({ error: err.message });
  }
}


// ─── POST /api/predict ─────────────────────────────────────────
async function predictOnDemand(req, res) {
  const { machineId, machine_id } = req.body;
  const mid = machineId || machine_id || 'UNKNOWN';
  try {
    const { predictMachineRisk } = require('../lib/aiPredictionService');
    const result = await predictMachineRisk(mid, req.body);
    
    const mappedResult = {
      status: result.status,
      niveau: result.status,
      prob_panne: result.risk_percentage,
      scenario_label: result.type_panne,
      panne_type: result.type_panne,
      action_recommandee: result.recommandation,
      notification_message: result.diagnostic,
      rul_estime: result.details?.rul_cycles ?? 0,
      confiance: 0.95,
      heat_risk: result.details?.heat_risk ?? 0,
      vibration_risk: result.details?.vibration_risk ?? 0,
      details: result.details
    };
    
    res.json(mappedResult);
  } catch (error) {
    console.error('Erreur predictOnDemand:', error);
    res.status(500).json({ error: 'Erreur lors de la prédiction en temps réel' });
  }
}

module.exports = {
  getPredictions,
  getLatestPrediction,
  getCriticalMachines,
  getPredictionStats,
  predictOnDemand
};
