const mongoose = require('mongoose');
const MaintenanceAgent = require('./src/models/MaintenanceAgent');

async function listAllAgents() {
    try {
        await mongoose.connect('mongodb://127.0.0.1:27017/dali_pfe');
        
        const agents = await MaintenanceAgent.find({});
        console.log(`Nombre total d'agents: ${agents.length}`);
        
        agents.forEach(a => {
            console.log(`Agent: ${a.firstName} ${a.lastName} (ID: ${a.maintenanceAgentId})`);
            console.log(`Machines: ${a.machineIds.join(', ')}`);
            console.log('---');
        });

        process.exit(0);
    } catch (err) {
        console.error(err);
        process.exit(1);
    }
}

listAllAgents();
