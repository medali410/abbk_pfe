/**
 * Migre les anciens documents `users` avec role CONCEPTION vers la collection `concepteurs`,
 * en conservant le même _id (jetons JWT inchangés jusqu'à expiration).
 *
 * Usage : npm run migrate:concepteurs
 * Utilise l'API driver (sans schéma User) pour lire les anciens rôles supprimés de l'enum.
 */
const mongoose = require('mongoose');
require('dotenv').config();

const Concepteur = require('./src/models/Concepteur');

async function main() {
    const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe';
    await mongoose.connect(uri);
    console.log('MongoDB:', uri.replace(/:[^:@/]+@/, ':****@'));

    const usersColl = mongoose.connection.db.collection('users');
    const users = await usersColl.find({ role: 'CONCEPTION' }).toArray();

    if (users.length === 0) {
        console.log('[OK] Aucun document users { role: CONCEPTION } à migrer.');
        await mongoose.disconnect();
        process.exit(0);
        return;
    }

    let migrated = 0;
    for (const u of users) {
        const exists = await Concepteur.findById(u._id).lean();
        if (exists) {
            console.log('[SKIP] concepteurs déjà _id', String(u._id), u.email);
            await usersColl.deleteOne({ _id: u._id });
            continue;
        }
        const email = (u.email || '').toString().trim().toLowerCase();
        const clash = email && (await Concepteur.findOne({ email }));
        if (clash) {
            console.warn('[WARN] Email déjà dans concepteurs — User laissé tel quel:', u.email);
            continue;
        }
        await Concepteur.collection.insertOne({
            _id: u._id,
            email: u.email,
            username: u.username,
            password: u.password,
            companyId: u.companyId,
            machineIds: u.machineIds || [],
            location: u.location,
            specialite: u.specialite,
            imageUrl: u.imageUrl,
            createdAt: u.createdAt || new Date(),
            updatedAt: u.updatedAt || new Date(),
        });
        await usersColl.deleteOne({ _id: u._id });
        migrated += 1;
        console.log('[OK] Migré → concepteurs:', u.email);
    }

    console.log('\nTerminé. Migrés:', migrated, '/', users.length);
    await mongoose.disconnect();
    process.exit(0);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
