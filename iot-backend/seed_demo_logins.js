/**
 * Crée / met à jour des comptes de démonstration pour tester l’app (MongoDB doit tourner).
 *
 * Lance :  npm run seed:demo
 *
 * Identifiants (email = champ « identifiant » sur l’écran de connexion) :
 *   - Super admin     : superadmin@dali-pfe.com  / DaliPfe2026!
 *   - Client entreprise : client.demo@dali-pfe.com / DaliPfe2026!
 *   - Technicien      : tech.demo@dali-pfe.com     / DaliPfe2026!
 *   - Maintenance (concepteur, collection concepteurs) : maintenance.demo@dali-pfe.com / DaliPfe2026!
 */

const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const User = require('./src/models/User');
const Concepteur = require('./src/models/Concepteur');
const Client = require('./src/models/Client');
const Technician = require('./src/models/Technician');
const Machine = require('./src/models/Machine');

const CLIENT_ID = 'CLI-DEMO-001';
const MACHINE_ID = 'MAC-DEMO-001';
const DEMO_PASSWORD = 'DaliPfe2026!';

async function upsertClient() {
    const email = 'client.demo@dali-pfe.com';
    const hash = await bcrypt.hash(DEMO_PASSWORD, 10);
    let doc = await Client.findOne({ clientId: CLIENT_ID });
    if (!doc) {
        doc = await Client.create({
            clientId: CLIENT_ID,
            name: 'Client Démo DALI',
            email,
            password: hash,
            address: 'Zone industrielle — Tunis, TN',
            location: 'Siège démo',
            motorType: 'EL_M',
            machines: 0,
            techs: 0,
        });
        console.log('✅ Client créé:', CLIENT_ID);
    } else {
        await Client.updateOne(
            { _id: doc._id },
            {
                $set: {
                    email,
                    password: hash,
                    name: doc.name || 'Client Démo DALI',
                    address: doc.address || 'Zone industrielle — Tunis, TN',
                },
            }
        );
        console.log('✅ Client mis à jour:', CLIENT_ID);
    }
    return Client.findOne({ clientId: CLIENT_ID });
}

async function upsertMachine() {
    const existing = await Machine.findById(MACHINE_ID);
    if (!existing) {
        await Machine.create({
            _id: MACHINE_ID,
            name: 'Machine démo ligne A',
            status: 'RUNNING',
            location: 'Atelier démo',
            companyId: CLIENT_ID,
            motorType: 'EL_M',
            lastMaintenance: new Date(),
        });
        console.log('✅ Machine créée:', MACHINE_ID);
    } else {
        await Machine.updateOne(
            { _id: MACHINE_ID },
            {
                $set: {
                    companyId: CLIENT_ID,
                    name: existing.name || 'Machine démo ligne A',
                },
            }
        );
        console.log('✅ Machine alignée sur client démo:', MACHINE_ID);
    }
}

async function upsertTechnician() {
    const email = 'tech.demo@dali-pfe.com';
    const hash = await bcrypt.hash(DEMO_PASSWORD, 10);
    const fullName = 'Jean Dupont Démo';
    let t = await Technician.findOne({ email });
    if (!t) {
        const year = new Date().getFullYear();
        const technicianId = `TECH-${year}-DEMO01`;
        t = await Technician.create({
            technicianId,
            name: fullName,
            email,
            password: hash,
            companyId: CLIENT_ID,
            machineIds: [MACHINE_ID],
            specialization: 'Maintenance prédictive — démo',
            status: 'Disponible',
        });
        console.log('✅ Technicien créé:', email, technicianId);
    } else {
        await Technician.updateOne(
            { _id: t._id },
            {
                $set: {
                    password: hash,
                    name: fullName,
                    companyId: CLIENT_ID,
                    machineIds: [MACHINE_ID],
                    specialization: t.specialization || 'Maintenance prédictive — démo',
                },
            }
        );
        console.log('✅ Technicien mis à jour:', email);
    }
}

async function upsertUser(email, username, role, extra = {}) {
    const hash = await bcrypt.hash(DEMO_PASSWORD, 10);
    await User.updateOne(
        { email },
        {
            $set: {
                email,
                username,
                password: hash,
                role,
                ...extra,
            },
        },
        { upsert: true }
    );
    console.log('✅ Compte User:', email, '(' + role + ')');
}

async function upsertConcepteurDemo() {
    const email = 'maintenance.demo@dali-pfe.com';
    const username = 'maintenance_demo';
    const hash = await bcrypt.hash(DEMO_PASSWORD, 10);
    await User.deleteMany({ email });
    await Concepteur.updateOne(
        { email },
        {
            $set: {
                email,
                username,
                password: hash,
                companyId: CLIENT_ID,
                location: 'Bureau conception / maintenance',
                machineIds: [MACHINE_ID],
                specialite: 'Maintenance & conception — démo',
            },
        },
        { upsert: true }
    );
    console.log('✅ Compte Concepteur:', email, '(collection concepteurs)');
}

async function syncClientCounts() {
    const mCount = await Machine.countDocuments({ companyId: CLIENT_ID });
    const techCount = await Technician.countDocuments({ companyId: CLIENT_ID });
    await Client.updateOne(
        { clientId: CLIENT_ID },
        { $set: { machines: mCount, techs: techCount } }
    );
}

async function main() {
    const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe';
    await mongoose.connect(uri);
    console.log('MongoDB:', uri.replace(/:[^:@/]+@/, ':****@'));

    await upsertClient();
    await upsertMachine();
    await upsertTechnician();

    await upsertUser('superadmin@dali-pfe.com', 'superadmin_demo', 'SUPER_ADMIN', {
        companyId: '',
        location: 'Siège',
    });
    await upsertConcepteurDemo();

    await syncClientCounts();

    console.log('\n========== Connexion app (http://localhost:3001 /api/login) ==========');
    console.log('Super admin   | superadmin@dali-pfe.com       | ' + DEMO_PASSWORD);
    console.log('Client        | client.demo@dali-pfe.com      | ' + DEMO_PASSWORD);
    console.log('Technicien    | tech.demo@dali-pfe.com        | ' + DEMO_PASSWORD);
    console.log('Concepteur    | concepteur.demo@dali-pfe.com | ' + DEMO_PASSWORD + '  (npm run seed:dev-concepteur)');
    console.log('Maintenance   | maintenance.demo@dali-pfe.com | ' + DEMO_PASSWORD + '  (concepteurs + machines démo)');
    console.log('Client ID (API) : ' + CLIENT_ID);
    console.log('=======================================================================\n');

    await mongoose.disconnect();
    process.exit(0);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
