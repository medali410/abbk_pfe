// ============================================================
//  ABBKA - API IA Prédictive Standalone (Port 3001)
//  Utilise Gemini + Dataset AI4I 2020 dans MongoDB
// ============================================================

const express = require('express');
const cors = require('cors');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const { MongoClient } = require('mongodb');

const app = express();
app.use(cors());
app.use(express.json());

// ==================== CONFIGURATION ====================
const GEMINI_API_KEY = 'AIzaSyAVR3Uu7s-wQ3We4j-fSRSbK4zATDittGI';
const MONGO_URI = 'mongodb://localhost:27017/';
const PORT = 3001;

// ==================== INITIALISATION ====================
const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });

let db, trainingCollection, historyCollection;

MongoClient.connect(MONGO_URI)
    .then(client => {
        db = client.db('abbka');
        trainingCollection = db.collection('training_data');
        historyCollection = db.collection('prediction_history');
        console.log('✅ MongoDB connecté - collections prêtes');
    })
    .catch(err => console.error('❌ Erreur MongoDB:', err.message));

// ==================== FONCTION PRÉDICTION ====================
async function predictWithGemini(currentData) {
    const thermal = parseFloat(currentData.thermal) || 25;

    const similarCases = await trainingCollection.find({
        'metrics.thermal': { $gte: thermal - 5, $lte: thermal + 5 }
    }).limit(10).toArray();

    const statsArr = await trainingCollection.aggregate([{
        $group: {
            _id: null,
            avgTemp: { $avg: '$metrics.thermal' },
            avgPressure: { $avg: '$metrics.pressure' },
            avgPower: { $avg: '$metrics.power' },
            failureRate: { $avg: '$failure.machine_failure' },
            totalSamples: { $sum: 1 }
        }
    }]).toArray();

    const ds = statsArr[0] || { avgTemp: 26.9, avgPressure: 4.0, avgPower: 75, failureRate: 0.034, totalSamples: 10000 };

    const casesText = similarCases.slice(0, 5).map((c, i) => {
        const types = [
            c.failure?.hdf ? 'Thermique' : '',
            c.failure?.pwf ? 'Électrique' : '',
            c.failure?.twf ? 'Usure' : '',
            c.failure?.osf ? 'Surcharge' : ''
        ].filter(Boolean).join(',') || 'Aucune';
        return `Exemple ${i + 1}: Temp=${c.metrics?.thermal}°C, Press=${c.metrics?.pressure}bar, Puiss=${c.metrics?.power}kW => ${c.failure?.machine_failure ? '❌ PANNE (' + types + ')' : '✅ OK'}`;
    }).join('\n');

    const prompt = `Tu es un expert en maintenance prédictive industrielle analysant des données de machines.

DONNÉES ACTUELLES DE LA MACHINE :
- Température        : ${currentData.thermal ?? '-'}°C
- Humidité          : ${currentData.humidity ?? '-'}%
- Pression          : ${currentData.pressure ?? '-'} bar
- Puissance         : ${currentData.power ?? '-'} kW
- Distance sécurité : ${currentData.ultrasonic ?? '-'} cm
- Présence humaine  : ${currentData.presence ? 'OUI' : 'NON'}
- Infrarouge        : ${currentData.infrared ?? '-'}°C

STATISTIQUES DU DATASET (${ds.totalSamples} machines réelles) :
- Température moyenne      : ${(ds.avgTemp || 0).toFixed(1)}°C
- Pression moyenne         : ${(ds.avgPressure || 0).toFixed(1)} bar
- Puissance moyenne        : ${(ds.avgPower || 0).toFixed(1)} kW
- Taux de panne historique : ${((ds.failureRate || 0) * 100).toFixed(1)}%

CAS SIMILAIRES HISTORIQUES (température ±5°C) :
${casesText || 'Aucun cas similaire trouvé dans le dataset'}

SEUILS NORMAUX : Température max 40°C | Pression max 8 bar | Puissance max 80 kW

TÂCHE : Analyse ces données et prédit la probabilité de panne.

Réponds UNIQUEMENT en JSON valide (sans markdown) :
{"failure_probability":<0-100>,"risk_level":"<CRITIQUE|ELEVE|MOYEN|FAIBLE|MINIMAL>","predicted_failure_type":"<type de panne probable>","time_to_failure":"<estimation temps avant panne>","recommended_action":"<action recommandée>","confidence":<0-100>,"reasoning":"<explication de l'analyse en français>"}`;

    try {
        const result = await model.generateContent(prompt);
        const text = result.response.text();
        const jsonMatch = text.match(/\{[\s\S]*?\}/);
        if (!jsonMatch) throw new Error('Pas de JSON dans la réponse Gemini');
        const prediction = JSON.parse(jsonMatch[0]);
        prediction.model = 'Gemini-1.5-Flash';
        prediction.dataset_samples = ds.totalSamples;
        prediction.similar_cases_found = similarCases.length;
        prediction.timestamp = new Date().toISOString();
        return prediction;
    } catch (error) {
        console.error('Erreur Gemini:', error.message);
        return {
            failure_probability: (currentData.thermal > 40 || currentData.pressure > 8) ? 75 : 15,
            risk_level: currentData.thermal > 40 ? 'CRITIQUE' : 'FAIBLE',
            predicted_failure_type: 'Analyse fallback',
            time_to_failure: 'Indéterminé',
            recommended_action: 'Surveillance normale',
            confidence: 50,
            similar_cases_found: similarCases.length,
            reasoning: 'Gemini API indisponible - analyse de base par règles',
            model: 'Fallback-Rules',
            dataset_samples: ds.totalSamples,
            timestamp: new Date().toISOString(),
            error: error.message
        };
    }
}

// ==================== ENDPOINTS ====================
app.post('/api/predict', async (req, res) => {
    try {
        console.log('\n📊 Requête de prédiction:', req.body.machineId || 'machine ?');
        const prediction = await predictWithGemini(req.body);
        console.log('✅ Risque:', prediction.risk_level, `(${prediction.failure_probability}%)`);

        // Save history to MongoDB
        if (historyCollection) {
            await historyCollection.insertOne({
                machineId: req.body.machineId,
                timestamp: new Date(),
                prediction: prediction,
                input_data: req.body
            });
        }

        res.json({ success: true, prediction });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

app.get('/api/dataset/stats', async (req, res) => {
    try {
        const global = await trainingCollection.aggregate([
            { $group: { _id: null, total: { $sum: 1 }, failures: { $sum: '$failure.machine_failure' }, avgTemp: { $avg: '$metrics.thermal' }, avgPressure: { $avg: '$metrics.pressure' }, avgPower: { $avg: '$metrics.power' } } }
        ]).toArray();
        const byType = await trainingCollection.aggregate([
            { $group: { _id: '$type', count: { $sum: 1 }, failureRate: { $avg: '$failure.machine_failure' } } },
            { $sort: { _id: 1 } }
        ]).toArray();
        res.json({ global: global[0] || {}, byType });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/dataset/samples', async (req, res) => {
    try {
        const limit = Math.min(parseInt(req.query.limit) || 20, 100);
        const filter = req.query.failures === '1' ? { 'failure.machine_failure': 1 } : {};
        const samples = await trainingCollection.find(filter).limit(limit).toArray();
        res.json(samples);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/health', (req, res) => {
    res.json({
        status: 'healthy',
        model: 'Gemini-1.5-Flash',
        database: db ? 'connected' : 'disconnected',
        gemini_key_configured: GEMINI_API_KEY !== 'VOTRE_CLE_GEMINI_ICI'
    });
});

app.get('/api/predict/history/:machineId', async (req, res) => {
    try {
        const machineId = req.params.machineId;
        if (!historyCollection) return res.status(500).json({ success: false, error: "DB non connectée" });

        const history = await historyCollection.find({ machineId: machineId })
            .sort({ timestamp: -1 })
            .limit(20)
            .toArray();
        res.json({ success: true, history: history });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// ==================== DÉMARRAGE ====================
app.listen(PORT, () => {
    console.log(`
╔════════════════════════════════════════════════════════╗
║       🤖 ABBKA - API IA PRÉDICTIVE (Standalone)        ║
║                                                        ║
║  🌐 Serveur   : http://localhost:${PORT}                  ║
║  🧠 Modèle    : Google Gemini 1.5 Flash               ║
║  📦 Dataset   : MongoDB abbka.training_data            ║
║                                                        ║
║  Endpoints :                                           ║
║  POST /api/predict           → Prédiction IA           ║
║  GET  /api/dataset/stats     → Statistiques dataset    ║
║  GET  /api/dataset/samples   → Exemples dataset        ║
║  GET  /api/health            → Santé API               ║
╚════════════════════════════════════════════════════════╝
  `);
});
