const mongoose = require('mongoose');
const DiagnosticIntervention = require('./src/models/DiagnosticIntervention');
require('dotenv').config();

async function check() {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/dali_pfe');
    
    const ints = await DiagnosticIntervention.find({ machineId: 'MAC-1775750118162' }).sort({ createdAt: -1 }).limit(5);
    ints.forEach(i => {
        console.log(`ID: ${i._id}, Status: ${i.status}, Technician: ${i.technicianName}, CreatedAt: ${i.createdAt}`);
    });
    
    await mongoose.disconnect();
}

check();
