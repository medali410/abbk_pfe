// ============================================================
//  ABBKA - Import Dataset AI4I 2020 dans MongoDB (Node.js)
//  Fichier : import_dataset.js
// ============================================================

const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');
const readline = require('readline');

const MONGO_URI = 'mongodb://localhost:27017/abbka';
const COLLECTION_NAME = 'training_data';
const CSV_FILE = path.join(__dirname, 'ai4i2020.csv');

// ==================== SCHEMA ====================
const trainingSchema = new mongoose.Schema({
    udi: Number,
    product_id: String,
    type: String,
    metrics: {
        thermal: Number,
        process_temp: Number,
        rotational_speed: Number,
        torque: Number,
        tool_wear: Number,
        pressure: Number,
        power: Number
    },
    failure: {
        machine_failure: Number,
        twf: Number,
        hdf: Number,
        pwf: Number,
        osf: Number,
        rnf: Number
    },
    timestamp: Date,
    source: String,
    imported_at: Date
});

const Training = mongoose.model('training_data', trainingSchema, COLLECTION_NAME);

// ==================== MAIN ====================
async function main() {
    console.log('╔════════════════════════════════════════════════════════╗');
    console.log('║       ABBKA - Import Dataset Training (Node.js)       ║');
    console.log('╚════════════════════════════════════════════════════════╝\n');

    if (!fs.existsSync(CSV_FILE)) {
        console.error('❌ Fichier ai4i2020.csv introuvable dans:', __dirname);
        console.error('\n📥 Télécharger le dataset :');
        console.error('   https://archive.ics.uci.edu/ml/machine-learning-databases/00601/ai4i2020.csv');
        console.error('   Ou Kaggle: https://www.kaggle.com/datasets/stephanmatzka/predictive-maintenance-dataset-ai4i-2020\n');
        console.error('   Placez le fichier dans:', __dirname);
        process.exit(1);
    }

    // Connexion MongoDB
    await mongoose.connect(MONGO_URI);
    console.log('📦 MongoDB connecté');

    // Vider la collection
    await Training.deleteMany({});
    console.log('🗑️  Collection vidée\n');

    // Lire le CSV — collecter toutes les lignes d'abord
    const lines = await new Promise((resolve, reject) => {
        const result = [];
        const rl = readline.createInterface({ input: fs.createReadStream(CSV_FILE), crlfDelay: Infinity });
        rl.on('line', line => { if (line.trim()) result.push(line); });
        rl.on('close', () => resolve(result));
        rl.on('error', reject);
    });

    let headers = null;
    let records = [];
    let lineCount = 0;
    let totalInserted = 0;

    for (const line of lines) {
        if (!line.trim()) continue;
        const cols = line.split(',').map(c => c.trim().replace(/^"|"$/g, ''));

        if (!headers) {
            headers = cols;
            console.log('[1/4] En-têtes CSV :', headers.join(', '));
            continue;
        }

        const row = {};
        headers.forEach((h, i) => row[h] = cols[i]);

        const record = {
            udi: parseInt(row['UDI'] || lineCount),
            product_id: row['Product ID'] || `PROD_${lineCount}`,
            type: row['Type'] || 'M',
            metrics: {
                thermal: parseFloat((parseFloat(row['Air temperature [K]'] || 300) - 273.15).toFixed(1)),
                process_temp: parseFloat((parseFloat(row['Process temperature [K]'] || 310) - 273.15).toFixed(1)),
                rotational_speed: parseInt(row['Rotational speed [rpm]'] || 1500),
                torque: parseFloat(parseFloat(row['Torque [Nm]'] || 40).toFixed(2)),
                tool_wear: parseInt(row['Tool wear [min]'] || 0),
                pressure: parseFloat((parseFloat(row['Torque [Nm]'] || 40) / 10.0).toFixed(2)),
                power: parseFloat((parseFloat(row['Rotational speed [rpm]'] || 1500) / 20.0).toFixed(1))
            },
            failure: {
                machine_failure: parseInt(row['Machine failure'] || 0),
                twf: parseInt(row['TWF'] || 0),
                hdf: parseInt(row['HDF'] || 0),
                pwf: parseInt(row['PWF'] || 0),
                osf: parseInt(row['OSF'] || 0),
                rnf: parseInt(row['RNF'] || 0)
            },
            timestamp: new Date(),
            source: 'AI4I_2020_Dataset',
            imported_at: new Date()
        };

        records.push(record);
        lineCount++;

        if (records.length >= 1000) {
            await Training.insertMany(records);
            totalInserted += records.length;
            process.stdout.write(`\r  📥 ${totalInserted} enregistrements insérés...`);
            records = [];
        }
    }

    if (records.length > 0) {
        await Training.insertMany(records);
        totalInserted += records.length;
    }

    console.log(`\n  📥 Total: ${totalInserted} enregistrements insérés`);

    // ==================== STATS ====================
    const total = await Training.countDocuments();
    const failures = await Training.countDocuments({ 'failure.machine_failure': 1 });
    const pct = ((failures / total) * 100).toFixed(1);

    console.log('\n╔════════════════════════════════════════════════════════╗');
    console.log(`║  ✅ IMPORT TERMINÉ                                     ║`);
    console.log(`║  📊 Total enregistrements : ${String(total).padEnd(8)}                 ║`);
    console.log(`║  ⚠️  Pannes détectées     : ${String(failures).padEnd(8)} (${pct}%)          ║`);
    console.log('╚════════════════════════════════════════════════════════╝');

    // Créer les index
    console.log('\n[INDEX] Création des index MongoDB...');
    await mongoose.connection.collection(COLLECTION_NAME).createIndex({ udi: 1 });
    await mongoose.connection.collection(COLLECTION_NAME).createIndex({ timestamp: 1 });
    await mongoose.connection.collection(COLLECTION_NAME).createIndex({ 'failure.machine_failure': 1 });
    console.log('  ✅ Index créés');

    // Statistiques par type
    console.log('\n[STATS] Répartition par type de machine :');
    const stats = await Training.aggregate([
        {
            $group: {
                _id: '$type',
                count: { $sum: 1 },
                avg_temp: { $avg: '$metrics.thermal' },
                failure_rate: { $avg: '$failure.machine_failure' }
            }
        },
        { $sort: { _id: 1 } }
    ]);

    stats.forEach(s => {
        console.log(`  Type ${s._id} : ${s.count} samples | Temp moy: ${s.avg_temp.toFixed(1)}°C | Taux panne: ${(s.failure_rate * 100).toFixed(1)}%`);
    });

    console.log('\n✅ Prêt pour l\'entraînement IA !\n');
    await mongoose.disconnect();
    process.exit(0);
}

main().catch(err => {
    console.error('❌ Erreur:', err.message);
    process.exit(1);
});
