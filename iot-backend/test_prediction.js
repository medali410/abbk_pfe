// ============================================================
//  Test de l'API Prédictive
// ============================================================

const axios = require('axios');

const API_URL = 'http://localhost:3001';

async function testPrediction() {
    console.log('╔════════════════════════════════════════════════════════╗');
    console.log('║       TEST API PRÉDICTIVE ABBKA                        ║');
    console.log('╚════════════════════════════════════════════════════════╝\n');

    // Test 1 : Machine normale
    console.log('📊 Test 1 : Machine en fonctionnement NORMAL');
    const normalData = {
        thermal: 25.5,
        humidity: 60,
        pressure: 4.2,
        power: 45,
        ultrasonic: 150,
        presence: 0,
        magnetic: 1,
        infrared: 26.75
    };

    try {
        const res1 = await axios.post(`${API_URL}/api/predict`, normalData);
        console.log('✅ Résultat:', res1.data.prediction);
        console.log(`   Probabilité panne: ${res1.data.prediction.failure_probability}%`);
        console.log(`   Risque: ${res1.data.prediction.risk_level}`);
        console.log(`   Action: ${res1.data.prediction.recommended_action}\n`);
    } catch (error) {
        console.error('❌ Erreur:', error.message);
    }

    // Test 2 : Machine critique
    console.log('📊 Test 2 : Machine en état CRITIQUE');
    const criticalData = {
        thermal: 45.5,
        humidity: 85,
        pressure: 9.2,
        power: 92,
        ultrasonic: 15,
        presence: 1,
        magnetic: 0,
        infrared: 46.75
    };

    try {
        const res2 = await axios.post(`${API_URL}/api/predict`, criticalData);
        console.log('✅ Résultat:', res2.data.prediction);
        console.log(`   Probabilité panne: ${res2.data.prediction.failure_probability}%`);
        console.log(`   Risque: ${res2.data.prediction.risk_level}`);
        console.log(`   Action: ${res2.data.prediction.recommended_action}\n`);
    } catch (error) {
        console.error('❌ Erreur:', error.message);
    }

    // Test 3 : Statistiques dataset
    console.log('📊 Test 3 : Statistiques du dataset');
    try {
        const res3 = await axios.get(`${API_URL}/api/dataset/stats`);
        console.log('✅ Statistiques:', res3.data);
    } catch (error) {
        console.error('❌ Erreur:', error.message);
    }
}

testPrediction();
