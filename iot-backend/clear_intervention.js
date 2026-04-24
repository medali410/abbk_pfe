const mongoose = require('mongoose');
const DiagnosticIntervention = require('./src/models/DiagnosticIntervention');
const Machine = require('./src/models/Machine');
require('dotenv').config();

async function clearIntervention() {
    try {
        await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/dali_pfe');
        console.log('Connected to DB');
        
        const machineId = 'MAC-1775750118162';
        const result = await DiagnosticIntervention.deleteMany({ machineId: machineId });
        console.log(`Deleted ${result.deletedCount} interventions for machine ${machineId}`);
        
        await Machine.findOneAndUpdate({ machineId: machineId }, { status: 'RUNNING' });
        console.log('Machine status reset to RUNNING');
        
        await mongoose.disconnect();
    } catch (err) {
        console.error(err);
    }
}

clearIntervention();
