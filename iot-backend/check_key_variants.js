const { GoogleGenerativeAI } = require('@google/generative-ai');

const GEMINI_API_KEY = 'AIzaSyAAe1OGZmMyoUSRpKIY9kkgpoRiBElyy1s';
const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);

async function listSupportedModels() {
    console.log('Testing key validity through discovery...');
    try {
        // We can't list models directly with this SDK easily without an endpoint, 
        // but we can try a few more variants.
        const modelNames = ['gemini-pro', 'gemini-1.0-pro', 'gemini-1.5-flash', 'gemini-1.5-pro'];
        for (const name of modelNames) {
            console.log(`Checking ${name}...`);
            const model = genAI.getGenerativeModel({ model: name });
            try {
                const result = await model.generateContent('ping');
                console.log(`✅ Success with ${name}!`);
                return;
            } catch (e) {
                console.log(`❌ ${name} failed: ${e.message}`);
                if (e.message.includes('API key not valid')) {
                    console.log('--- CRITICAL: API KEY IS INVAlID ---');
                    return;
                }
            }
        }
    } catch (err) {
        console.error('Fetch error:', err.message);
    }
}

listSupportedModels();
