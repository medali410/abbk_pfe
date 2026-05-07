/* eslint-disable no-console */
/**
 * Suppression manuelle d'un client par identifiant CLI-XXXX (ou _id Mongo).
 * Usage:
 *   node delete_client.js CLI-2026-196
 *   node delete_client.js 65a1234567890abcdef12345
 *
 * - Reprend la connexion MongoDB du serveur (MONGO_URI sinon mongodb://127.0.0.1:27017/dali_pfe).
 * - Affiche les techniciens / agents maintenance / machines / demandes d'achat liés.
 * - Demande confirmation interactive avant la suppression effective du client.
 */

require('dotenv').config();
const readline = require('readline');
const mongoose = require('mongoose');

const Client = require('./src/models/Client');
const Technician = require('./src/models/Technician');
const MaintenanceAgent = require('./src/models/MaintenanceAgent');

let Machine = null;
try {
    Machine = require('./src/models/Machine');
} catch (_) {
    Machine = mongoose.model('Machine', new mongoose.Schema({}, { strict: false }));
}

let PurchaseRequest = null;
try {
    PurchaseRequest = require('./src/models/PurchaseRequest');
} catch (_) {
    /* optional */
}

async function connect() {
    const atlasUri = process.env.MONGO_URI;
    const localUri = 'mongodb://127.0.0.1:27017/dali_pfe';
    if (atlasUri) {
        try {
            await mongoose.connect(atlasUri, { serverSelectionTimeoutMS: 5000 });
            console.log('✅ MongoDB Atlas connecté');
            return;
        } catch (err) {
            console.warn('⚠️  Atlas indisponible, repli local:', err.message);
        }
    }
    await mongoose.connect(localUri, { serverSelectionTimeoutMS: 5000 });
    console.log('✅ MongoDB Local connecté');
}

function ask(question) {
    return new Promise((resolve) => {
        const rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout,
        });
        rl.question(question, (answer) => {
            rl.close();
            resolve(String(answer || '').trim());
        });
    });
}

async function findClient(input) {
    const raw = String(input).trim();
    if (!raw) return null;
    let client = await Client.findOne({ clientId: raw });
    if (!client && mongoose.Types.ObjectId.isValid(raw)) {
        client = await Client.findById(raw);
    }
    return client;
}

async function listLinked(client) {
    const cid = String(client.clientId || '').trim();
    const _id = String(client._id);
    const orQuery = [];
    if (cid) orQuery.push({ companyId: cid });
    orQuery.push({ companyId: _id });

    const [techs, agents, machines] = await Promise.all([
        Technician.find({ $or: orQuery }).select('_id name technicianId email contactEmail'),
        MaintenanceAgent.find({
            $or: [
                ...(cid ? [{ clientId: cid }] : []),
                { clientId: _id },
            ],
        }).select('_id firstName lastName maintenanceAgentId email'),
        Machine.find({ $or: orQuery }).select('_id name companyId'),
    ]);

    let pending = [];
    if (PurchaseRequest) {
        pending = await PurchaseRequest.find({
            $or: [
                ...(cid ? [{ linkedClientId: cid }] : []),
                { linkedClientId: _id },
            ],
        }).select('_id machineName requesterName status requestType');
    }

    return { techs, agents, machines, pending };
}

async function run() {
    const arg = process.argv[2];
    if (!arg) {
        console.error('Usage : node delete_client.js <CLI-XXXX|_id>');
        process.exit(1);
    }

    await connect();

    const client = await findClient(arg);
    if (!client) {
        console.error(`❌ Aucun client trouvé pour: ${arg}`);
        await mongoose.disconnect();
        process.exit(2);
    }

    console.log('\n📌 Client cible :');
    console.log(`   _id        : ${client._id}`);
    console.log(`   clientId   : ${client.clientId}`);
    console.log(`   name       : ${client.name}`);
    console.log(`   email      : ${client.email}`);
    console.log(`   provider   : ${client.provider || '-'}`);

    const { techs, agents, machines, pending } = await listLinked(client);
    console.log(`\n🔗 Techniciens liés         : ${techs.length}`);
    techs.forEach((t) =>
        console.log(`   - ${t.technicianId || t._id} | ${t.name} | ${t.email}`)
    );
    console.log(`🔗 Agents maintenance liés  : ${agents.length}`);
    agents.forEach((a) =>
        console.log(
            `   - ${a.maintenanceAgentId || a._id} | ${a.firstName || ''} ${a.lastName || ''} | ${a.email}`
        )
    );
    console.log(`🔗 Machines liées           : ${machines.length}`);
    machines.forEach((m) =>
        console.log(`   - ${m._id} | ${m.name || '-'} | companyId=${m.companyId}`)
    );
    if (PurchaseRequest) {
        console.log(`🔗 Demandes d'achat liées   : ${pending.length}`);
        pending.forEach((p) =>
            console.log(
                `   - ${p._id} | ${p.requesterName} | ${p.machineName} | ${p.status} | ${p.requestType || '-'}`
            )
        );
    }

    const answer = await ask(
        `\n⚠️  Confirmer la suppression de ${client.clientId} (${client.name}) ? ` +
            `tape OUI pour confirmer : `
    );
    if (answer.toUpperCase() !== 'OUI') {
        console.log('Suppression annulée.');
        await mongoose.disconnect();
        return;
    }

    const result = await Client.deleteOne({ _id: client._id });
    console.log(`\n🗑️  Client supprimé: deletedCount=${result.deletedCount}`);
    console.log(
        '   (Les techniciens, agents maintenance, machines et demandes liés ne sont PAS supprimés.\n' +
            '    Ouvrez Compass pour les nettoyer manuellement si besoin.)'
    );

    await mongoose.disconnect();
}

run().catch(async (err) => {
    console.error('❌ Erreur:', err);
    try {
        await mongoose.disconnect();
    } catch (_) {}
    process.exit(1);
});
