const { GoogleGenerativeAI } = require('@google/generative-ai');

const GEMINI_API_KEY = 'AIzaSyAVR3Uu7s-wQ3We4j-fSRSbK4zATDittGI';
const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);

async function probeModels() {
    const models = [
        'gemini-1.5-flash',
        'gemini-1.5-pro',
        'gemini-pro',
        'gemini-1.0-pro'
    ];

    console.log('--- GEMINI PROBE ---');
    for (const modelName of models) {
        console.log(`Testing model: ${modelName}...`);
        try {
            const model = genAI.getGenerativeModel({ model: modelName });
            const result = await model.generateContent('Hi');
            console.log(`✅ SUCCESS with ${modelName}:`, result.response.text());
            return; // Stop if one works
        } catch (error) {
            console.log(`❌ FAILED with ${modelName}: ${error.message}`);
        }
    }
}

probeModels();
