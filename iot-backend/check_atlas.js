require('dotenv').config();
const mongoose = require('mongoose');

async function testAtlas() {
    const uri = process.env.MONGO_URI;
    console.log('Testing Atlas connection with URI:', uri.split('@')[1] || uri);
    try {
        await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
        console.log('✅ SUCCESS: Connected to MongoDB Atlas');
        const db = mongoose.connection.db;
        const collections = await db.listCollections().toArray();
        console.log('Collections found:', collections.map(c => c.name));
    } catch (err) {
        console.error('❌ FAILURE:', err.message);
        if (err.message.includes('IP address is not whitelisted')) {
            console.log('\nSUGGESTION: Please whitelist your IP in MongoDB Atlas console.');
        }
    } finally {
        await mongoose.disconnect();
    }
}

testAtlas();
