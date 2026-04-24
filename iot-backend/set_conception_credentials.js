/**
 * Compte concepteur alternatif (tests manuels) : conception@dali-pfe.com / Test@123.
 * Collection `concepteurs` — distincte des documents CAO (`conceptions`).
 *
 * Démo recommandée : npm run seed:demo puis npm run seed:dev-concepteur
 * (concepteur.demo@dali-pfe.com, mot de passe DaliPfe2026! ou DEMO_PASSWORD).
 */
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const Concepteur = require('./src/models/Concepteur');
const User = require('./src/models/User');
const Machine = require('./src/models/Machine');

const CLIENT_ID = process.env.DEMO_CLIENT_ID || 'CLI-DEMO-001';

async function run() {
  await mongoose.connect(process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe');

  const machines = await Machine.find({ companyId: CLIENT_ID }).select('_id').lean().limit(20);
  const machineIds = machines.map((m) => String(m._id)).filter(Boolean);
  if (machineIds.length === 0) {
    console.warn('[WARN] Aucune machine pour', CLIENT_ID, '— pour l’Observatory : npm run seed:demo');
  }

  const email = 'conception@dali-pfe.com';
  const username = 'conception_test';
  const password = 'Test@123';
  const hashed = await bcrypt.hash(password, 10);

  await User.deleteMany({ $or: [{ email }, { username }] });

  const $set = {
    email,
    username,
    password: hashed,
    companyId: CLIENT_ID,
    location: 'Bureau Conception',
  };
  if (machineIds.length) {
    $set.machineIds = machineIds;
  }

  await Concepteur.updateOne({ email }, { $set }, { upsert: true });

  console.log('CONCEPTEUR_ACCOUNT_READY', { email, username, password, collection: 'concepteurs', machineCount: machineIds.length });
  await mongoose.disconnect();
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
