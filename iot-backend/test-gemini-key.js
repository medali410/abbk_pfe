const { GoogleGenerativeAI } = require('@google/generative-ai');

require('dotenv').config();
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'AIzaSyAVR3Uu7s-wQ3We4j-fSRSbK4zATDittGI';

const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });

async function testKey() {
    console.log('🧪 Test de la clé API Gemini...\n');

    try {
        const result = await model.generateContent('Réponds simplement "OK" si tu me reçois');
        const text = result.response.text();

        console.log('✅ CLÉ API VALIDE !');
        console.log('Réponse Gemini :', text);
        console.log('\n✅ L\'intégration IA fonctionnera correctement\n');

    } catch (error) {
        console.error('❌ CLÉ API INVALIDE !');
        console.error('Erreur :', error.message);
        console.log('\n⚠️  Actions à faire :');
        console.log('1. Vérifier la clé sur https://aistudio.google.com/apikey');
        console.log('2. Remplacer GEMINI_API_KEY dans server.js');
        console.log('3. Relancer le serveur\n');
    }
}

testKey();
