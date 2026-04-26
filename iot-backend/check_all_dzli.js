const mongoose = require('mongoose');
const DiagnosticIntervention = require('./src/models/DiagnosticIntervention');
require('dotenv').config();

async function checkAll() {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/dali_pfe');
    
    const ints = await DiagnosticIntervention.find({ machineId: 'DZLI' }).sort({ createdAt: -1 }).limit(3);
    ints.forEach(i => {
        console.log(`ID: ${i._id}, Status: ${i.status}, CreatedAt: ${i.createdAt}`);
    });
    
    await mongoose.disconnect();
}

checkAll();
