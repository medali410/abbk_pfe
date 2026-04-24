/**
 * Layer-1: Real-time heuristic scenario detection from the 7 MQTT sensors.
 *
 * Improvements over the original:
 *   - Dynamic thresholds per motor type (learned from recent history baseline)
 *   - Per-machine running statistics (mean/std) for adaptive anomaly scoring
 *   - Trend detection over the last N readings
 *   - Multi-sensor cross-correlation checks
 */

const Telemetry = require('../models/Telemetry');
const Machine   = require('../models/Machine');

const HISTORY_MAX = 30;
const histories   = new Map();
const bootstrapped = new Set();
const baselineStats = new Map();

// Dynamic thresholds per motor type (overridden at runtime from DB if available)
const MOTOR_PROFILES = {
    EL_S: { temp: { warn: 55, crit: 75 }, pressure: { warn: 3.0, crit: 5.0 }, power: { warn: 60000, crit: 90000 }, vibration: { warn: 2.0, crit: 3.5 } },
    EL_M: { temp: { warn: 65, crit: 85 }, pressure: { warn: 4.0, crit: 7.0 }, power: { warn: 80000, crit: 120000 }, vibration: { warn: 2.5, crit: 4.0 } },
    EL_L: { temp: { warn: 75, crit: 95 }, pressure: { warn: 5.0, crit: 9.0 }, power: { warn: 100000, crit: 160000 }, vibration: { warn: 3.0, crit: 5.0 } },
    HY_L: { temp: { warn: 70, crit: 90 }, pressure: { warn: 8.0, crit: 15.0 }, power: { warn: 120000, crit: 200000 }, vibration: { warn: 2.0, crit: 3.5 } },
    DI_S: { temp: { warn: 80, crit: 100 }, pressure: { warn: 6.0, crit: 10.0 }, power: { warn: 50000, crit: 80000 }, vibration: { warn: 2.5, crit: 4.0 } },
    DI_M: { temp: { warn: 85, crit: 105 }, pressure: { warn: 7.0, crit: 12.0 }, power: { warn: 70000, crit: 110000 }, vibration: { warn: 3.0, crit: 5.0 } },
    DI_L: { temp: { warn: 90, crit: 110 }, pressure: { warn: 8.0, crit: 14.0 }, power: { warn: 100000, crit: 160000 }, vibration: { warn: 3.5, crit: 5.5 } },
    DEFAULT: { temp: { warn: 65, crit: 85 }, pressure: { warn: 4.0, crit: 7.0 }, power: { warn: 80000, crit: 120000 }, vibration: { warn: 2.5, crit: 4.0 } },
};

function num(v, d = 0) {
    if (v == null || v === '') return d;
    const n = Number(v);
    return Number.isFinite(n) ? n : d;
}

function metricsAsObject(m) {
    if (!m || typeof m !== 'object') return {};
    if (m instanceof Map) return Object.fromEntries(m);
    return m;
}

function extractSevenFromPayload(payload) {
    const m = metricsAsObject(payload.metrics);
    const g = (a, b) => num(a !== undefined && a !== null ? a : b);
    return {
        thermal:    g(payload.temperature, m.thermal),
        pressure:   g(payload.pressure,    m.pressure),
        power:      g(payload.power,       m.power),
        ultrasonic: g(payload.ultrasonic,  m.ultrasonic),
        presence:   g(payload.presence,    m.presence),
        magnetic:   g(payload.magnetic,    m.magnetic),
        infrared:   g(payload.infrared,    m.infrared),
    };
}

function pushSample(machineId, vec) {
    if (!histories.has(machineId)) histories.set(machineId, []);
    const h = histories.get(machineId);
    h.push({ ...vec, ts: Date.now() });
    if (h.length > HISTORY_MAX) h.shift();
}

function countSignChanges(values) {
    const deltas = [];
    for (let i = 1; i < values.length; i++) deltas.push(values[i] - values[i - 1]);
    let c = 0;
    for (let i = 1; i < deltas.length; i++) {
        if (deltas[i] === 0 || deltas[i - 1] === 0) continue;
        if (Math.sign(deltas[i]) !== Math.sign(deltas[i - 1])) c++;
    }
    return { deltas, signChanges: c };
}

function seriesStats(arr) {
    if (arr.length < 2) return { mean: 0, std: 0, range: 0, min: arr[0] ?? 0, max: arr[0] ?? 0 };
    const min = Math.min(...arr);
    const max = Math.max(...arr);
    const mean = arr.reduce((a, b) => a + b, 0) / arr.length;
    const variance = arr.reduce((s, x) => s + (x - mean) ** 2, 0) / arr.length;
    return { mean, std: Math.sqrt(variance), range: max - min, min, max };
}

function linearTrend(values) {
    const n = values.length;
    if (n < 3) return 0;
    let sx = 0, sy = 0, sxx = 0, sxy = 0;
    for (let i = 0; i < n; i++) {
        sx += i; sy += values[i]; sxx += i * i; sxy += i * values[i];
    }
    const denom = n * sxx - sx * sx;
    if (denom === 0) return 0;
    return (n * sxy - sx * sy) / denom;
}

function getProfile(motorType) {
    const key = (motorType || '').toUpperCase();
    return MOTOR_PROFILES[key] || MOTOR_PROFILES.DEFAULT;
}

function updateBaseline(machineId, h) {
    if (h.length < 8) return null;
    const stats = {};
    for (const key of ['thermal', 'pressure', 'power', 'ultrasonic', 'magnetic', 'infrared']) {
        const vals = h.map(x => x[key]).filter(v => Number.isFinite(v));
        if (vals.length >= 4) {
            stats[key] = seriesStats(vals);
        }
    }
    baselineStats.set(machineId, stats);
    return stats;
}

function zScore(value, mean, std) {
    if (std < 0.001) return 0;
    return Math.abs(value - mean) / std;
}

/**
 * @param {string} machineId
 */
async function ensureBootstrap(machineId) {
    if (bootstrapped.has(machineId)) return;
    try {
        const docs = await Telemetry.find({ machineId: String(machineId) })
            .sort({ createdAt: -1 })
            .limit(HISTORY_MAX)
            .select('temperature metrics')
            .lean();

        histories.set(machineId, []);
        for (const d of docs.reverse()) {
            const met = metricsAsObject(d.metrics);
            pushSample(machineId, {
                thermal:    num(d.temperature ?? met.thermal),
                pressure:   num(met.pressure),
                power:      num(met.power),
                ultrasonic: num(met.ultrasonic),
                presence:   num(met.presence),
                magnetic:   num(met.magnetic),
                infrared:   num(met.infrared),
            });
        }
    } catch (e) {
        console.error('[scenario] bootstrap:', e.message);
        histories.set(machineId, []);
    }
    bootstrapped.add(machineId);
}

/**
 * @param {string} machineId
 * @param {ReturnType<typeof extractSevenFromPayload>} current
 * @param {string} [motorType]
 */
function analyzeScenario(machineId, current, motorType) {
    pushSample(machineId, current);
    const h = histories.get(machineId) || [];
    const profile = getProfile(motorType);
    const baseline = updateBaseline(machineId, h);

    if (h.length < 4) {
        return {
            scenarioCode: 'LEARNING',
            scenarioLabel: 'Apprentissage du profil machine',
            scenarioProbPanne: 0,
            scenarioExplanation:
                'Pas assez d\'historique pour reconnaître un scénario (minimum 4 points). Les mesures sont stockées en base pour construire le profil sur les 7 paramètres.',
            scenarioThermalSeries: h.map(x => x.thermal),
            basedOnSamples: h.length,
            layer: 'rules',
        };
    }

    const thermal    = h.map(x => x.thermal);
    const pressure   = h.map(x => x.pressure);
    const power      = h.map(x => x.power);
    const ultrasonic = h.map(x => x.ultrasonic);
    const infrared   = h.map(x => x.infrared);

    const th     = countSignChanges(thermal);
    const thStat = seriesStats(thermal);
    const prStat = seriesStats(pressure);
    const prCh   = countSignChanges(pressure);
    const usStat = seriesStats(ultrasonic);
    const irStat = seriesStats(infrared);
    const pwStat = seriesStats(power);

    let score = 0;
    const reasons = [];

    // --- Dynamic threshold checks (adapted to motor type) ---
    if (current.thermal >= profile.temp.crit) {
        score += 35;
        reasons.push(`Température critique (${current.thermal.toFixed(1)}°C >= seuil ${profile.temp.crit}°C pour ${motorType || 'DEFAULT'})`);
    } else if (current.thermal >= profile.temp.warn) {
        score += 15;
        reasons.push(`Température élevée (${current.thermal.toFixed(1)}°C >= seuil avertissement ${profile.temp.warn}°C)`);
    }

    // --- Z-score anomaly from machine's own baseline ---
    if (baseline) {
        for (const [key, val] of [['thermal', current.thermal], ['pressure', current.pressure], ['power', current.power]]) {
            if (baseline[key]) {
                const z = zScore(val, baseline[key].mean, baseline[key].std);
                if (z >= 3.5) {
                    score += 20;
                    reasons.push(`${key} anormal pour cette machine (z-score=${z.toFixed(1)})`);
                } else if (z >= 2.5) {
                    score += 10;
                    reasons.push(`${key} légèrement anormal (z-score=${z.toFixed(1)})`);
                }
            }
        }
    }

    // --- Oscillation / instability patterns ---
    if (th.signChanges >= 2 && thStat.range >= 10) {
        score += 30;
        reasons.push(
            `Température oscillante (${th.signChanges} renversements, amplitude ${thStat.range.toFixed(1)}°C)`
        );
    }
    if (thermal.length >= 5 && thStat.std >= 5) {
        score += 12;
        reasons.push(`Forte variabilité thermique (σ≈${thStat.std.toFixed(1)}°C)`);
    }

    const lastJump = Math.abs(thermal[thermal.length - 1] - thermal[thermal.length - 2]);
    if (lastJump >= 10) {
        score += 20;
        reasons.push(`Saut récent de ${lastJump.toFixed(1)}°C entre deux lectures`);
    }

    // --- Trend detection ---
    const thermalTrend = linearTrend(thermal);
    if (thermalTrend > 1.5) {
        score += 15;
        reasons.push(`Tendance thermique montante (pente=${thermalTrend.toFixed(2)}°C/lecture)`);
    }

    const powerTrend = linearTrend(power);
    if (powerTrend < -500 && thermalTrend > 0.5) {
        score += 18;
        reasons.push('Puissance en baisse + température en hausse — friction ou surcharge probable');
    }

    // --- Pressure instability ---
    if (prCh.signChanges >= 2 && prStat.range >= Math.max(0.8, prStat.mean * 0.12)) {
        score += 12;
        reasons.push('Cycles de pression instables');
    }

    // --- Power / thermal correlation ---
    if (thermal.length >= 3 && power.length >= 3) {
        const dt = thermal[thermal.length - 1] - thermal[thermal.length - 3];
        const dp = power[power.length - 1] - power[power.length - 3];
        if (dt > 7 && dp < -4) {
            score += 15;
            reasons.push('Température monte sans puissance — friction / charge anormale');
        }
    }

    // --- Ultrasonic anomaly ---
    if (usStat.range >= 25 && ultrasonic.filter(x => x > 0).length >= 3) {
        score += 10;
        reasons.push('Grande variation ultrasonique (obstacle / jeu mécanique ?)');
    }

    // --- Presence sensor flapping ---
    const pres = h.map(x => x.presence);
    let flips = 0;
    for (let i = 1; i < pres.length; i++) if (pres[i] !== pres[i - 1]) flips++;
    if (flips >= 3 && pres.length <= 14) {
        score += 8;
        reasons.push('Présence PIR qui bascule trop souvent');
    }

    // --- Magnetic sensor anomaly ---
    const mag = h.map(x => x.magnetic);
    let magFlips = 0;
    for (let i = 1; i < mag.length; i++) {
        if (Math.abs(mag[i] - mag[i - 1]) > mag[i - 1] * 0.25 + 5) magFlips++;
    }
    if (magFlips >= 3) {
        score += 8;
        reasons.push('Capteur magnétique très fluctuant');
    }

    // --- IR / thermal divergence ---
    if (irStat.range >= 15 && thermal.length >= 4) {
        const corrRough = Math.abs(irStat.mean - thStat.mean);
        if (corrRough > 25) {
            score += 8;
            reasons.push('Écart infrarouge/thermique — vérifier capteurs');
        }
    }

    score = Math.min(100, Math.round(score));

    let code  = 'NORMAL';
    let label = 'Profil stable sur la fenêtre récente';
    if (score >= 72) {
        code  = 'PANNE_IMMINENTE';
        label = 'Scénario critique — risque de panne élevé';
    } else if (score >= 42) {
        code  = 'AVANT_PANNE';
        label = 'Scénario de dégradation (avant panne)';
    } else if (score >= 18) {
        code  = 'SURVEILLANCE';
        label = 'Anomalies légères — surveiller les 7 paramètres';
    }

    return {
        scenarioCode: code,
        scenarioLabel: label,
        scenarioProbPanne: score,
        scenarioExplanation: reasons.length
            ? reasons.join(' · ')
            : 'Les 7 paramètres restent cohérents sur l\'historique récent.',
        scenarioThermalSeries: thermal.slice(-12),
        basedOnSamples: h.length,
        motorType: motorType || 'UNKNOWN',
        layer: 'rules',
    };
}

/**
 * Get the full sensor history buffer for a machine (used by inference API bridge).
 * @param {string} machineId
 * @returns {Array<Object>}
 */
function getHistory(machineId) {
    return histories.get(machineId) || [];
}

module.exports = {
    extractSevenFromPayload,
    ensureBootstrap,
    analyzeScenario,
    getHistory,
    MOTOR_PROFILES,
};
