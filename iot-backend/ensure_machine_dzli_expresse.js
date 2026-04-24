/**
 * Crée la machine « dzli » (MAC-1775750118162) rattachée au client Expresse si absente.
 * Prérequis : npm run seed:expresse
 *
 *   node ensure_machine_dzli_expresse.js
 */
const mongoose = require('mongoose');
require('dotenv').config();

const Client = require('./src/models/Client');
const Machine = require('./src/models/Machine');

const MACHINE_ID = 'MAC-1775750118162';
const CLIENT_HINT = { $or: [{ clientId: 'CLI-EXPRESSE-001' }, { email: 'expresse@dali-pfe.com' }] };

async function main() {
    const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe';
    await mongoose.connect(uri);

    const client = await Client.findOne(CLIENT_HINT);
    if (!client) {
        console.error('Client Expresse introuvable. Lance : npm run seed:expresse');
        process.exit(1);
    }

    const companyId = client.clientId || String(client._id);
    const existing = await Machine.findById(MACHINE_ID);

    if (!existing) {
        await Machine.create({
            _id: MACHINE_ID,
            name: 'dzli',
            status: 'RUNNING',
            location: 'Site Expresse — ligne convoyeur',
            companyId,
            motorType: 'EL_M',
            type: 'Convoyeur',
        });
        await Client.updateOne({ _id: client._id }, { $inc: { machines: 1 } });
        console.log('OK — machine créée:', MACHINE_ID, '| client:', companyId);
    } else {
        await Machine.updateOne(
            { _id: MACHINE_ID },
            {
                $set: {
                    companyId,
                    name: existing.name || 'dzli',
                    motorType: existing.motorType || 'EL_M',
                },
            },
        );
        console.log('OK — machine déjà présente, profil aligné:', MACHINE_ID);
    }

    await mongoose.disconnect();
    process.exit(0);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
