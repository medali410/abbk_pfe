const mongoose = require('mongoose');
const MaintenanceAgent = require('./src/models/MaintenanceAgent');

async function findAgents() {
    try {
        await mongoose.connect('mongodb://127.0.0.1:27017/dali_pfe');
        console.log('Connecté à MongoDB');

        const machineId = 'MAC-1775750118162';
        console.log(`Recherche des agents pour la machine: ${machineId}`);

        const agents = await MaintenanceAgent.find({ 
            machineIds: { $in: [machineId] } 
        });

        if (agents.length === 0) {
            console.log('Aucun agent de maintenance trouvé pour cette machine.');
        } else {
            console.log(`Trouvé ${agents.length} agent(s):`);
            agents.forEach(a => {
                console.log(`- ${a.firstName} ${a.lastName} (ID: ${a.maintenanceAgentId}, Email: ${a.email})`);
            });
        }

        process.exit(0);
    } catch (err) {
        console.error(err);
        process.exit(1);
    }
}

findAgents();
