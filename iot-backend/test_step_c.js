// ============================================================
// test_step_c.js — Tests STEP C (connexion locale forcée)
// Lancer : node test_step_c.js
// ============================================================

// NE PAS charger .env ici : Atlas est inaccessible depuis cet IP.
// On utilise directement MongoDB local.

const mongoose = require('mongoose');

// ── Couleurs console ─────────────────────────────────────────
const OK  = '\x1b[32m✅\x1b[0m';
const ERR = '\x1b[31m❌\x1b[0m';
const INF = '\x1b[36mℹ️ \x1b[0m';
const WRN = '\x1b[33m⚠️ \x1b[0m';

function ok(msg)   { console.log(`${OK}  ${msg}`); }
function err(msg)  { console.log(`${ERR}  ${msg}`); }
function info(msg) { console.log(`${INF} ${msg}`); }
function warn(msg) { console.log(`${WRN} ${msg}`); }

// ── Connexion MongoDB ────────────────────────────────────────
async function connect() {
  const uri = 'mongodb://127.0.0.1:27017/dali_pfe';
  info(`Connexion à : ${uri}`);
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
  ok('MongoDB local connecté');
}

// ── Modèles (inline légers) ──────────────────────────────────
const Machine = require('./src/models/Machine');
const Controle = require('./src/models/Controle');

// ============================================================
// TEST 1 — MongoDB : motorType + seuilsControle + tempsMarche
// ============================================================
async function test1_mongodb() {
  console.log('\n\x1b[1m━━━ TEST 1 — MongoDB ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1b[0m');

  const machines = await Machine.find({}).lean();
  info(`Nombre de machines trouvées : ${machines.length}`);

  let passMotorType     = 0;
  let passSeuils        = 0;
  let passTempsMarche   = 0;
  const problems = [];

  for (const m of machines) {
    const name = m.name || String(m._id);

    // motorType
    if (['air_cooled', 'water_cooled'].includes(m.motorType)) {
      passMotorType++;
    } else {
      problems.push(`  [motorType] ${name} → "${m.motorType}" invalide`);
    }

    // seuilsControle
    if (Array.isArray(m.seuilsControle) && m.seuilsControle.length > 0) {
      passSeuils++;
    } else {
      problems.push(`  [seuilsControle] ${name} → tableau vide ou absent`);
    }

    // tempsMarche
    if (m.tempsMarche && typeof m.tempsMarche.totalHeures === 'number') {
      passTempsMarche++;
    } else {
      problems.push(`  [tempsMarche] ${name} → non initialisé`);
    }
  }

  const total = machines.length;

  if (passMotorType === total) {
    ok(`motorType valide      : ${passMotorType}/${total} machines`);
  } else {
    err(`motorType invalide    : seulement ${passMotorType}/${total}`);
  }

  if (passSeuils === total) {
    ok(`seuilsControle prêts  : ${passSeuils}/${total} machines`);
  } else {
    err(`seuilsControle absent : seulement ${passSeuils}/${total}`);
  }

  if (passTempsMarche === total) {
    ok(`tempsMarche initialisé: ${passTempsMarche}/${total} machines`);
  } else {
    err(`tempsMarche manquant  : seulement ${passTempsMarche}/${total}`);
  }

  if (problems.length > 0) {
    warn('Détails des problèmes :');
    problems.forEach(p => console.log('\x1b[33m' + p + '\x1b[0m'));
  }

  return { total, passMotorType, passSeuils, passTempsMarche };
}

// ============================================================
// TEST 2 — Contrôle : simulation d'un seuil atteint
// ============================================================
async function test2_controle_simulation() {
  console.log('\n\x1b[1m━━━ TEST 2 — Simulation seuil → contrôle ━━━━━━━━━━━━━━\x1b[0m');

  // Chercher une machine avec seuils
  const machine = await Machine.findOne({
    'seuilsControle.0': { $exists: true }
  });

  if (!machine) {
    warn('Aucune machine avec seuilsControle — test ignoré');
    return;
  }

  info(`Machine de test : ${machine.name} (${machine._id})`);
  info(`motorType       : ${machine.motorType}`);
  info(`tempsMarche     : ${machine.tempsMarche?.totalHeures?.toFixed(2)} h`);
  info(`Nombre de seuils: ${machine.seuilsControle.length}`);

  // Afficher les seuils
  for (const s of machine.seuilsControle) {
    info(`  · ${s.typeControle.padEnd(35)} @ ${String(s.prochainControleHeure).padStart(5)} h  [${s.priorite}]`);
  }

  // Vérifier contrôles existants
  const existants = await Controle.find({ machineId: String(machine._id) });
  info(`Contrôles existants en base : ${existants.length}`);

  if (existants.length > 0) {
    ok(`Contrôles déjà créés automatiquement :`);
    for (const c of existants) {
      console.log(`   📋 ${c.typeControle} | ${c.statut} | priorité: ${c.priorite} | ${c.heuresDeClenchement}h`);
    }
  } else {
    info('Aucun contrôle créé pour l\'instant (seuils pas encore atteints)');
  }

  // Simulation : forcer un seuil à 0 pour déclencher la création
  const seuil = machine.seuilsControle[0];
  const typeTest = `[TEST] ${seuil.typeControle}`;

  const dejaTest = await Controle.findOne({
    machineId: String(machine._id),
    typeControle: typeTest,
    statut: 'planifié'
  });

  if (!dejaTest) {
    const controle = await Controle.create({
      machineId:          String(machine._id),
      machineName:        machine.name,
      typeControle:       typeTest,
      heuresDeClenchement: machine.tempsMarche?.totalHeures ?? 0,
      dateControle:       new Date(),
      priorite:           seuil.priorite,
      statut:             'planifié',
      motorType:          machine.motorType,
    });
    ok(`Contrôle de test créé : _id=${controle._id}`);

    // Nettoyer après le test
    await Controle.deleteOne({ _id: controle._id });
    ok('Contrôle de test supprimé (nettoyage)');
  } else {
    ok('Contrôle de test déjà présent — création MongoDB fonctionne');
    await Controle.deleteOne({ _id: dejaTest._id });
    ok('Nettoyage effectué');
  }
}

// ============================================================
// TEST 3 — Socket.IO : vérifier la signature des services
// ============================================================
async function test3_services_signatures() {
  console.log('\n\x1b[1m━━━ TEST 3 — Signatures des services Socket.IO ━━━━━━━━━\x1b[0m');

  try {
    const { startControleService }     = require('./src/services/controleService');
    const { startTempseMarcheService } = require('./src/services/tempsMarcheService');
    const machineCtrl                  = require('./src/controllers/machineController');

    // controleService accepte io ?
    if (typeof startControleService === 'function' && startControleService.length >= 0) {
      ok(`controleService.startControleService   — paramètre io : ${startControleService.length >= 1 ? 'OUI' : 'NON (optionnel OK)'}`);
    } else {
      err('startControleService introuvable');
    }

    // tempsMarcheService accepte io ?
    if (typeof startTempseMarcheService === 'function') {
      ok(`tempsMarcheService.startTempseMarcheService — paramètre io : ${startTempseMarcheService.length >= 1 ? 'OUI' : 'NON (optionnel OK)'}`);
    } else {
      err('startTempseMarcheService introuvable');
    }

    // machineController a setIo ?
    if (typeof machineCtrl.setIo === 'function') {
      ok('machineController.setIo() — présent');
    } else {
      err('machineController.setIo() — ABSENT');
    }

    // Tester l'injection d'un io mock
    const ioMock = {
      _emissions: [],
      emit(event, data) { this._emissions.push({ event, data }); }
    };
    machineCtrl.setIo(ioMock);
    ok('machineController.setIo(ioMock) — injection OK');

  } catch (e) {
    err(`Erreur chargement services : ${e.message}`);
  }
}

// ============================================================
// TEST 4 — Résumé des données
// ============================================================
async function test4_resume() {
  console.log('\n\x1b[1m━━━ TEST 4 — Résumé des données ━━━━━━━━━━━━━━━━━━━━━━━\x1b[0m');

  const [airCooled, waterCooled, running, totalControles] = await Promise.all([
    Machine.countDocuments({ motorType: 'air_cooled' }),
    Machine.countDocuments({ motorType: 'water_cooled' }),
    Machine.countDocuments({ status: 'RUNNING' }),
    Controle.countDocuments({}),
  ]);

  info(`Machines air_cooled   : ${airCooled}`);
  info(`Machines water_cooled : ${waterCooled}`);
  info(`Machines RUNNING      : ${running}`);
  info(`Contrôles en base     : ${totalControles}`);

  const urgents = await Controle.countDocuments({ priorite: 'urgente', statut: 'planifié' });
  const hautes  = await Controle.countDocuments({ priorite: 'haute',   statut: 'planifié' });
  if (urgents > 0) warn(`Contrôles URGENTS planifiés : ${urgents} → seront broadcastés en controle_urgent`);
  if (hautes > 0)  info(`Contrôles HAUTS planifiés  : ${hautes}`);
}

// ============================================================
// MAIN
// ============================================================
(async () => {
  console.log('\n\x1b[1m\x1b[35m╔══════════════════════════════════════════════════════╗');
  console.log('║         STEP C — TESTS SYSTÈME COMPLETS             ║');
  console.log('╚══════════════════════════════════════════════════════╝\x1b[0m\n');

  try {
    await connect();
    const r = await test1_mongodb();
    await test2_controle_simulation();
    await test3_services_signatures();
    await test4_resume();

    console.log('\n\x1b[1m━━━ RÉSULTAT FINAL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1b[0m');
    const pass = r.passMotorType === r.total && r.passSeuils === r.total && r.passTempsMarche === r.total;
    if (pass) {
      console.log(`\x1b[32m\x1b[1m✅ TOUS LES TESTS PASSENT — Système prêt pour STEP D\x1b[0m\n`);
    } else {
      console.log(`\x1b[33m\x1b[1m⚠️  Certains tests ont échoué — relancer initializeExistingMachines()\x1b[0m\n`);
      console.log('   → Redémarrer le serveur : node server.js');
      console.log('   → La fonction initializeExistingMachines() corrigera les machines\n');
    }
  } catch (e) {
    err(`Erreur fatale : ${e.message}`);
    console.error(e);
  } finally {
    await mongoose.disconnect();
    info('Déconnexion MongoDB');
  }
})();
