// fix_machines.js — Migration STEP C
// Corrige motorType + initialise tempsMarche + seuilsControle
// node fix_machines.js

const mongoose = require('mongoose');
const Machine  = require('./src/models/Machine');

const OK  = '\x1b[32m✅\x1b[0m';
const ERR = '\x1b[31m❌\x1b[0m';
const INF = '\x1b[36mℹ️ \x1b[0m';

// ── Seuils par défaut ──────────────────────────────────────────────────────
const seuilsAirCooled = [
  { typeControle: 'Contrôle filtre air',         intervalleHeures: 50,   prochainControleHeure: 50,   priorite: 'normale'  },
  { typeControle: 'Contrôle huile',               intervalleHeures: 100,  prochainControleHeure: 100,  priorite: 'haute'    },
  { typeControle: 'Contrôle courroie',            intervalleHeures: 250,  prochainControleHeure: 250,  priorite: 'normale'  },
  { typeControle: 'Nettoyage radiateur',          intervalleHeures: 300,  prochainControleHeure: 300,  priorite: 'normale'  },
  { typeControle: 'Révision générale',            intervalleHeures: 500,  prochainControleHeure: 500,  priorite: 'haute'    },
  { typeControle: 'Remplacement filtre air',      intervalleHeures: 1000, prochainControleHeure: 1000, priorite: 'urgente'  },
];

const seuilsWaterCooled = [
  { typeControle: 'Contrôle niveau eau',              intervalleHeures: 50,   prochainControleHeure: 50,   priorite: 'haute'    },
  { typeControle: 'Contrôle pompe eau',               intervalleHeures: 100,  prochainControleHeure: 100,  priorite: 'haute'    },
  { typeControle: 'Vérification circuit eau',         intervalleHeures: 200,  prochainControleHeure: 200,  priorite: 'normale'  },
  { typeControle: 'Changement liquide refroidissement', intervalleHeures: 500, prochainControleHeure: 500,  priorite: 'haute'   },
  { typeControle: 'Contrôle joints',                  intervalleHeures: 750,  prochainControleHeure: 750,  priorite: 'normale'  },
  { typeControle: 'Révision générale',                intervalleHeures: 1000, prochainControleHeure: 1000, priorite: 'urgente'  },
];

// Mots-clés → water_cooled (tout le reste → air_cooled)
const WATER_KEYWORDS = ['water', 'eau', 'liquide', 'refroid'];
function guessMotorType(raw) {
  const s = String(raw || '').toLowerCase();
  if (s === 'water_cooled') return 'water_cooled';
  if (s === 'air_cooled')   return 'air_cooled';
  if (WATER_KEYWORDS.some(k => s.includes(k))) return 'water_cooled';
  return 'air_cooled'; // défaut sûr
}

(async () => {
  console.log('\n\x1b[1m\x1b[35m╔══════════════════════════════════════════════════════╗');
  console.log('║       MIGRATION — Correction des machines            ║');
  console.log('╚══════════════════════════════════════════════════════╝\x1b[0m\n');

  try {
    await mongoose.connect('mongodb://127.0.0.1:27017/dali_pfe', { serverSelectionTimeoutMS: 5000 });
    console.log(`${OK}  MongoDB local connecté\n`);

    const machines = await Machine.find({});
    console.log(`${INF} ${machines.length} machines à traiter\n`);

    let updated = 0;

    for (const m of machines) {
      const name = m.name || String(m._id);
      let changed = false;

      // 1. Corriger motorType
      const oldType = m.motorType;
      if (!['air_cooled', 'water_cooled'].includes(oldType)) {
        m.motorType = guessMotorType(oldType);
        console.log(`${INF} [motorType] "${name}" : "${oldType}" → "${m.motorType}"`);
        changed = true;
      }

      // 2. Initialiser tempsMarche
      if (!m.tempsMarche || typeof m.tempsMarche.totalHeures !== 'number') {
        m.tempsMarche = { totalHeures: 0, derniereMiseAJour: new Date(), enMarche: false };
        console.log(`${INF} [tempsMarche] "${name}" initialisé à 0h`);
        changed = true;
      }

      // 3. Ajouter seuilsControle si vide
      if (!m.seuilsControle || m.seuilsControle.length === 0) {
        const seuils = m.motorType === 'water_cooled' ? seuilsWaterCooled : seuilsAirCooled;
        m.seuilsControle = seuils.map(s => ({ ...s, derniereVerificationHeure: 0 }));
        console.log(`${INF} [seuilsControle] "${name}" : ${m.seuilsControle.length} seuils ajoutés (${m.motorType})`);
        m.markModified('seuilsControle');
        changed = true;
      }

      if (changed) {
        await m.save();
        updated++;
        console.log(`${OK}  "${name}" → sauvegardé\n`);
      }
    }

    // ── Vérification finale ──────────────────────────────────────────────────
    console.log('\n\x1b[1m━━━ VÉRIFICATION FINALE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1b[0m');
    const total       = machines.length;
    const okMotor     = await Machine.countDocuments({ motorType: { $in: ['air_cooled', 'water_cooled'] } });
    const okSeuils    = await Machine.countDocuments({ 'seuilsControle.0': { $exists: true } });
    const okTemps     = await Machine.countDocuments({ 'tempsMarche.totalHeures': { $exists: true } });
    const airCooled   = await Machine.countDocuments({ motorType: 'air_cooled' });
    const waterCooled = await Machine.countDocuments({ motorType: 'water_cooled' });

    console.log(`${okMotor   === total ? OK : ERR}  motorType valide      : ${okMotor}/${total}`);
    console.log(`${INF} └─ air_cooled: ${airCooled}  |  water_cooled: ${waterCooled}`);
    console.log(`${okSeuils  === total ? OK : ERR}  seuilsControle prêts  : ${okSeuils}/${total}`);
    console.log(`${okTemps   === total ? OK : ERR}  tempsMarche initialisé: ${okTemps}/${total}`);

    console.log(`\n${OK}  Migration terminée — ${updated} machine(s) mise(s) à jour`);

    if (okMotor === total && okSeuils === total && okTemps === total) {
      console.log('\n\x1b[32m\x1b[1m🎉 TOUS LES TESTS PASSERONT — Relancer test_step_c.js pour confirmer\x1b[0m\n');
    }

  } catch (e) {
    console.error(`${ERR}  Erreur : ${e.message}`);
  } finally {
    await mongoose.disconnect();
    console.log(`${INF} Déconnexion`);
  }
})();
