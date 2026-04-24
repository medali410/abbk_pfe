const mongoose = require('mongoose');
const Machine = require('./src/models/Machine');
const MaintenanceAgent = require('./src/models/MaintenanceAgent');

async function findAgentsDeep() {
    try {
        await mongoose.connect('mongodb://127.0.0.1:27017/dali_pfe');
        
        const machine = await Machine.findOne({ _id: 'MAC-1775750118162' });
        if (!machine) {
            console.log('Machine non trouvée par _id MAC-1775750118162');
            // Try searching by name just in case
            const machineByName = await Machine.findOne({ name: /dzli/i });
            if (machineByName) {
                console.log(`Machine trouvée par nom "dzli": ${machineByName.name} (ID: ${machineByName._id})`);
                const agents = await MaintenanceAgent.find({ 
                    machineIds: { $in: [machineByName._id] } 
                });
                console.log(`Agents rattachés à cet ID: ${agents.length}`);
                agents.forEach(a => console.log(`- ${a.firstName} ${a.lastName}`));
            }
        } else {
            console.log(`Machine trouvée: ${machine.name} (ID: ${machine._id})`);
            const agents = await MaintenanceAgent.find({ 
                machineIds: { $in: [machine._id] } 
            });
            console.log(`Agents rattachés à cet ID: ${agents.length}`);
            agents.forEach(a => console.log(`- ${a.firstName} ${a.lastName}`));
        }

        process.exit(0);
    } catch (err) {
        console.error(err);
        process.exit(1);
    }
}

findAgentsDeep();
