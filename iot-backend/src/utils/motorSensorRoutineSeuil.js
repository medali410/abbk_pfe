/** Contrôle moteur / capteurs — périodicité : 7 j × 24 h de temps de marche cumulé */
const ROUTINE_TYPE = 'Contrôle routine capteurs moteur';
const ROUTINE_INTERVAL_HOURS = 168;

/** Condensateurs — périodicité : 3 j × 24 h de temps de marche cumulé */
const CONDENSATEUR_TYPE = 'Contrôle condensateurs';
const CONDENSATEUR_INTERVAL_HOURS = 72;

/**
 * Types dont la prochaine fiche n’est créée qu’au seuil temps de marche (controleService),
 * pas par anticipation calendaire après clôture.
 */
const PREVENTIVE_TEMPS_MARCHE_ONLY_TYPES = [ROUTINE_TYPE, CONDENSATEUR_TYPE];

/**
 * Ajoute le seuil préventif « capteurs moteur » si absent.
 * Ne modifie pas un seuil déjà présent (cycle en cours ou personnalisation).
 */
function ensureMotorSensorRoutineSeuil(machine) {
  if (!machine || typeof machine !== 'object') return false;
  const seuils = Array.isArray(machine.seuilsControle) ? [...machine.seuilsControle] : [];
  const idx = seuils.findIndex((s) => String(s.typeControle || '').trim() === ROUTINE_TYPE);
  if (idx >= 0) {
    const s = seuils[idx];
    if (Number(s.intervalleHeures) === 48) {
      s.intervalleHeures = ROUTINE_INTERVAL_HOURS;
      machine.seuilsControle = seuils;
      if (typeof machine.markModified === 'function') machine.markModified('seuilsControle');
      return true;
    }
    return false;
  }

  const totalHeures = Number(machine.tempsMarche?.totalHeures ?? 0);
  seuils.push({
    typeControle: ROUTINE_TYPE,
    intervalleHeures: ROUTINE_INTERVAL_HOURS,
    derniereVerificationHeure: 0,
    prochainControleHeure: totalHeures + ROUTINE_INTERVAL_HOURS,
    priorite: 'normale',
  });
  machine.seuilsControle = seuils;
  if (typeof machine.markModified === 'function') {
    machine.markModified('seuilsControle');
  }
  return true;
}

/**
 * Ajoute le seuil préventif « condensateurs » si absent.
 */
function ensureCondensateurRoutineSeuil(machine) {
  if (!machine || typeof machine !== 'object') return false;
  const seuils = Array.isArray(machine.seuilsControle) ? [...machine.seuilsControle] : [];
  const exists = seuils.some((s) => String(s.typeControle || '').trim() === CONDENSATEUR_TYPE);
  if (exists) return false;

  const totalHeures = Number(machine.tempsMarche?.totalHeures ?? 0);
  seuils.push({
    typeControle: CONDENSATEUR_TYPE,
    intervalleHeures: CONDENSATEUR_INTERVAL_HOURS,
    derniereVerificationHeure: 0,
    prochainControleHeure: totalHeures + CONDENSATEUR_INTERVAL_HOURS,
    priorite: 'haute',
  });
  machine.seuilsControle = seuils;
  if (typeof machine.markModified === 'function') {
    machine.markModified('seuilsControle');
  }
  return true;
}

async function ensureMotorSensorRoutineSeuilById(Machine, machineId) {
  const mid = String(machineId || '').trim();
  if (!mid) return;
  const machine = await Machine.findById(mid);
  if (!machine) return;
  const a = ensureMotorSensorRoutineSeuil(machine);
  const b = ensureCondensateurRoutineSeuil(machine);
  if (!a && !b) return;
  await machine.save();
}

module.exports = {
  ROUTINE_TYPE,
  ROUTINE_INTERVAL_HOURS,
  CONDENSATEUR_TYPE,
  CONDENSATEUR_INTERVAL_HOURS,
  PREVENTIVE_TEMPS_MARCHE_ONLY_TYPES,
  ensureMotorSensorRoutineSeuil,
  ensureCondensateurRoutineSeuil,
  ensureMotorSensorRoutineSeuilById,
};
