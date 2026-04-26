const mongoose = require('mongoose');
const DiagnosticIntervention = require('./src/models/DiagnosticIntervention');
require('dotenv').config();

async function checkIds() {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/dali_pfe');
    
    // Find active intervention for DZLI
    const int = await DiagnosticIntervention.findOne({ machineId: 'DZLI', status: { $in: ['OPEN', 'IN_PROGRESS'] } });
    if (int) {
        console.log('Active Intervention ID:', int._id.toString());
        console.log('Technician ID:', int.technicianId);
        console.log('Status:', int.status);
    } else {
        console.log('No active intervention for DZLI');
    }
    
    await mongoose.disconnect();
}

checkIds();
