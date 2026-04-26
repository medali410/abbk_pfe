const mongoose = require('mongoose');
const DiagnosticIntervention = require('./src/models/DiagnosticIntervention');
const Machine = require('./src/models/Machine');
require('dotenv').config();

async function checkByName() {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/dali_pfe');
    
    const machine = await Machine.findOne({ name: 'DZLI' });
    if (machine) {
        console.log('Machine found:', machine._id, machine.name);
        const ints = await DiagnosticIntervention.find({ machineId: machine._id.toString() }).sort({ createdAt: -1 }).limit(3);
        ints.forEach(i => {
            console.log(`ID: ${i._id}, Status: ${i.status}, CreatedAt: ${i.createdAt}`);
        });
    } else {
        console.log('Machine DZLI not found by name');
    }
    
    await mongoose.disconnect();
}

checkByName();
