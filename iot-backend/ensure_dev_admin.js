/**
 * Crée ou met à jour un super-admin local pour développement / démo.
 * Identifiants écran de connexion : admin / admin
 *
 * Usage : npm run seed:dev-admin
 * Prérequis : MongoDB (MONGO_URI dans .env ou défaut local)
 */
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const User = require('./src/models/User');

const DEV_EMAIL = 'admin';
const DEV_USERNAME = 'admin';
const DEV_PASSWORD = 'admin';

async function main() {
    const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe';
    await mongoose.connect(uri);
    console.log('MongoDB:', uri.replace(/:[^:@/]+@/, ':****@'));

    const hash = await bcrypt.hash(DEV_PASSWORD, 10);

    const res = await User.updateOne(
        { $or: [{ email: DEV_EMAIL }, { username: DEV_USERNAME }] },
        {
            $set: {
                email: DEV_EMAIL,
                username: DEV_USERNAME,
                password: hash,
                role: 'SUPER_ADMIN',
                companyId: '',
                location: 'Dev',
            },
        },
        { upsert: true }
    );

    if (res.upsertedCount) {
        console.log('[OK] Compte dev cree : email=admin password=admin (SUPER_ADMIN)');
    } else {
        console.log('[OK] Compte dev mis a jour : email=admin password=admin (SUPER_ADMIN)');
    }

    console.log('\nConnectez-vous dans l’app avec :');
    console.log('  Identifiant (champ email) : admin');
    console.log('  Mot de passe               : admin\n');

    await mongoose.disconnect();
    process.exit(0);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
