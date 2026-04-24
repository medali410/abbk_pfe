const mongoose = require('mongoose');
const Technician = require('./src/models/Technician');
const DiagnosticIntervention = require('./src/models/DiagnosticIntervention');

async function run() {
    await mongoose.connect('mongodb://127.0.0.1:27017/dali_pfe');
    
    const tech = await Technician.findOne({ email: 'tech.demo@dali-pfe.com' });
    if (!tech) {
        console.error('Tech demo not found');
        process.exit(1);
    }

    const machineId = 'MAC-1775750118162';
    
    // Close any previous interventions to avoid confusion
    await DiagnosticIntervention.updateMany(
        { machineId: machineId, status: { $ne: 'CLOSED' } },
        { $set: { status: 'CLOSED' } }
    );

    const intervention = new DiagnosticIntervention({
        machineId: machineId,
        companyId: 'CLI-2026-619',
        technicianId: tech._id,
        technicianName: tech.username || tech.name,
        summary: 'Maintenance critique DZLI - Test acceptance',
        priority: 'CRITICAL',
        scenarioType: 'THERMAL',
        scenarioLabel: 'Surchauffe thermique',
        status: 'OPEN'
    });

    await intervention.save();
    console.log('Assignment created for tech demo on machine dzli');
    process.exit(0);
}

run();
