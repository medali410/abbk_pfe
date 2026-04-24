/**
 * Migration Script: Add default parameters to all existing Machine documents
 * Run with: node migrate_machine_parameters.js
 */

const mongoose = require('mongoose');
require('dotenv').config();

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/iot-monitoring';

const DEFAULT_PARAMETERS = [
    { key: 'thermal', label: 'Température', unit: '°C', enabled: true, warnThreshold: 70, criticalThreshold: 85, icon: 'device-thermostat' },
    { key: 'pressure', label: 'Pression', unit: 'bar', enabled: false, warnThreshold: 3, criticalThreshold: 5, icon: 'speed' },
    { key: 'power', label: 'Puissance', unit: 'A', enabled: false, warnThreshold: 50, criticalThreshold: 80, icon: 'flash-on' },
    { key: 'ultrasonic', label: 'Ultrason', unit: 'cm', enabled: false, warnThreshold: 20, criticalThreshold: 10, icon: 'settings-input-antenna' },
    { key: 'presence', label: 'Présence', unit: '', enabled: false, warnThreshold: null, criticalThreshold: null, icon: 'person-pin' },
    { key: 'magnetic', label: 'Magnétique', unit: 'mT', enabled: false, warnThreshold: 50, criticalThreshold: 100, icon: 'radio-button-checked' },
    { key: 'infrared', label: 'Infrarouge', unit: '°C', enabled: false, warnThreshold: 60, criticalThreshold: 80, icon: 'wb-sunny' },
];

async function migrate() {
    console.log('🔌 Connexion à MongoDB...');
    await mongoose.connect(MONGO_URI);
    console.log('✅ Connecté à', MONGO_URI);

    const db = mongoose.connection.db;
    const machinesCollection = db.collection('machines');

    // Find machines that don't yet have a parameters field
    const machinesWithoutParams = await machinesCollection
        .find({ $or: [{ parameters: { $exists: false } }, { parameters: { $size: 0 } }] })
        .toArray();

    console.log(`\n📦 Machines sans paramètres trouvées : ${machinesWithoutParams.length}`);

    if (machinesWithoutParams.length === 0) {
        console.log('✅ Toutes les machines ont déjà des paramètres configurés.');
        await mongoose.disconnect();
        return;
    }

    console.log('\nMachines à migrer :');
    machinesWithoutParams.forEach(m => console.log(`  - [${m._id}] ${m.name}`));

    // Update all machines that are missing the parameters field
    const result = await machinesCollection.updateMany(
        { $or: [{ parameters: { $exists: false } }, { parameters: { $size: 0 } }] },
        { $set: { parameters: DEFAULT_PARAMETERS } }
    );

    console.log(`\n✅ Migration terminée : ${result.modifiedCount} machine(s) mise(s) à jour.`);

    // Verify
    const all = await machinesCollection.find({}).toArray();
    console.log('\n📊 État final des machines :');
    all.forEach(m => {
        const enabledCount = (m.parameters || []).filter(p => p.enabled).length;
        const totalCount = (m.parameters || []).length;
        console.log(`  - [${m._id}] ${m.name} → ${totalCount} paramètres (${enabledCount} activé(s))`);
    });

    await mongoose.disconnect();
    console.log('\n🔌 Déconnecté de MongoDB.');
}

migrate().catch(err => {
    console.error('❌ Erreur migration :', err);
    process.exit(1);
});
