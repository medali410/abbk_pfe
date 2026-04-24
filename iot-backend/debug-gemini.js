const { GoogleGenerativeAI } = require('@google/generative-ai');

const GEMINI_API_KEY = 'AIzaSyAAe1OGZmMyoUSRpKIY9kkgpoRiBElyy1s';
const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);

async function listModels() {
    try {
        const list = await genAI.getGenerativeModel({ model: 'models/gemini-1.5-flash' });
        // Note: genAI doesn't have a direct listModels, we usually use the model info or discovery
        // Better way to test key is just a simple prompt or check authentication
        console.log('Testing key with simple prompt...');
        const result = await list.generateContent('Hi');
        console.log('Success:', result.response.text());
    } catch (error) {
        console.error('Error details:', error);
    }
}

listModels();
