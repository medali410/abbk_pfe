const mongoose = require('mongoose');
const mongoURI = 'mongodb://127.0.0.1:27017/dali_pfe';

const TechnicianSchema = new mongoose.Schema({}, { strict: false });
const MaintenanceAgentSchema = new mongoose.Schema({}, { strict: false });
const MachineSchema = new mongoose.Schema({}, { strict: false });

const Technician = mongoose.model('Technician', TechnicianSchema);
const MaintenanceAgent = mongoose.model('MaintenanceAgent', MaintenanceAgentSchema);
const Machine = mongoose.model('Machine', MachineSchema);

async function run() {
  try {
    await mongoose.connect(mongoURI);
    console.log('Connected to MongoDB');

    const techs = await Technician.find({});
    const agents = await MaintenanceAgent.find({});
    const machines = await Machine.find({});

    console.log('\n--- TECHNICIANS ---');
    if (techs.length === 0) console.log('None found');
    techs.forEach(t => {
      console.log(`- Name: ${t.name}, ID: ${t.technicianId || t._id}, Machines: ${t.machineIds || t.machineId || 'None'}`);
    });

    console.log('\n--- MAINTENANCE AGENTS ---');
    if (agents.length === 0) console.log('None found');
    agents.forEach(a => {
      console.log(`- Name: ${a.name}, ID: ${a.maintenanceAgentId || a._id}, Machines: ${a.machineIds || 'None'}`);
    });

    console.log('\n--- MACHINES ---');
    machines.forEach(m => {
       console.log(`- Name: ${m.name}, ID: ${m.machineId || m._id}`);
    });

  } catch (err) {
    console.error(err);
  } finally {
    await mongoose.disconnect();
  }
}

run();
