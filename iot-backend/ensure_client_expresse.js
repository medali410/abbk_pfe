/**
 * Garantit un compte client login pour expresse@dali-pfe.com (évite 401 si absent ou mauvais mot de passe).
 *
 *   npm run seed:expresse
 *
 * Connexion app :  expresse@dali-pfe.com  /  123456
 */
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const Client = require('./src/models/Client');

const EMAIL = 'expresse@dali-pfe.com';
const PASSWORD = '123456';
const CLIENT_ID = 'CLI-EXPRESSE-001';
const NAME = 'expresse (Convoyeur)';

async function main() {
    const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe';
    await mongoose.connect(uri);
    const hash = await bcrypt.hash(PASSWORD, 10);

    const existing = await Client.findOne({
        $or: [{ email: EMAIL.toLowerCase() }, { clientId: CLIENT_ID }],
    });

    if (existing) {
        await Client.updateOne(
            { _id: existing._id },
            {
                $set: {
                    email: EMAIL.toLowerCase(),
                    password: hash,
                    name: existing.name || NAME,
                    ...(existing.clientId ? {} : { clientId: CLIENT_ID }),
                },
            }
        );
        console.log('OK — client mis à jour:', existing.clientId || CLIENT_ID, EMAIL);
    } else {
        await Client.create({
            clientId: CLIENT_ID,
            name: NAME,
            email: EMAIL.toLowerCase(),
            password: hash,
            address: 'Adresse démo — Tunisie',
            location: 'Site Expresse',
            motorType: 'EL_M',
            machines: 0,
            techs: 0,
        });
        console.log('OK — client créé:', CLIENT_ID, EMAIL);
    }

    console.log('\n  Login Flutter :  ' + EMAIL);
    console.log('  Mot de passe  :  ' + PASSWORD + '\n');

    await mongoose.disconnect();
    process.exit(0);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
