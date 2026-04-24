const mongoose = require('mongoose');
const DiagnosticIntervention = require('./src/models/DiagnosticIntervention');

async function findInterventions() {
    try {
        await mongoose.connect('mongodb://127.0.0.1:27017/dali_pfe');
        
        const machineId = 'MAC-1775750118162';
        const interventions = await DiagnosticIntervention.find({ machineId });
        
        console.log(`Nombre d'interventions pour dzli: ${interventions.length}`);
        
        interventions.forEach(i => {
            console.log(`Intervention ID: ${i._id}`);
            console.log(`Technicien assigné: ${i.technicianName} (ID: ${i.technicianId})`);
            console.log(`Statut: ${i.status}`);
            console.log('---');
        });

        process.exit(0);
    } catch (err) {
        console.error(err);
        process.exit(1);
    }
}

findInterventions();
