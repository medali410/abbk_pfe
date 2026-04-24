/**
 * Crée ou met à jour un compte concepteur (collection `concepteurs`) pour l’Observatory.
 * Même mot de passe que la démo seed:demo pour rester cohérent.
 *
 * Usage : npm run seed:dev-concepteur
 * Prérequis : MongoDB — de préférence npm run seed:demo (client + machine démo).
 */
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const Concepteur = require('./src/models/Concepteur');
const User = require('./src/models/User');
const Machine = require('./src/models/Machine');

const CLIENT_ID = process.env.DEMO_CLIENT_ID || 'CLI-DEMO-001';
const DEMO_PASSWORD = process.env.DEMO_PASSWORD || 'DaliPfe2026!';
const DEV_EMAIL = 'concepteur.demo@dali-pfe.com';
const DEV_USERNAME = 'concepteur_demo';

async function main() {
    const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe';
    await mongoose.connect(uri);
    console.log('MongoDB:', uri.replace(/:[^:@/]+@/, ':****@'));

    const machines = await Machine.find({ companyId: CLIENT_ID }).select('_id').lean().limit(20);
    const machineIds = machines.map((m) => String(m._id)).filter(Boolean);
    if (machineIds.length === 0) {
        console.warn('[WARN] Aucune machine pour', CLIENT_ID, '— lancez: npm run seed:demo');
    }

    const hash = await bcrypt.hash(DEMO_PASSWORD, 10);

    await User.deleteMany({ $or: [{ email: DEV_EMAIL }, { username: DEV_USERNAME }] });

    const res = await Concepteur.updateOne(
        { $or: [{ email: DEV_EMAIL }, { username: DEV_USERNAME }] },
        {
            $set: {
                email: DEV_EMAIL,
                username: DEV_USERNAME,
                password: hash,
                companyId: CLIENT_ID,
                location: 'Bureau conception — démo Observatory',
                machineIds: machineIds.length ? machineIds : undefined,
                specialite: 'Conception industrielle',
            },
        },
        { upsert: true }
    );

    if (res.upsertedCount) {
        console.log('[OK] Compte concepteur créé.');
    } else {
        console.log('[OK] Compte concepteur mis à jour.');
    }

    console.log('\nConnexion app (champ identifiant = email) :');
    console.log('  Email      :', DEV_EMAIL);
    console.log('  Mot de passe:', DEMO_PASSWORD);
    console.log('  Collection : concepteurs → dashboard /conception-observatory');
    console.log('  Machines   :', machineIds.length ? machineIds.join(', ') : '(aucune — seed:demo)');
    console.log('');

    await mongoose.disconnect();
    process.exit(0);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
