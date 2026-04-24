const mongoose = require('mongoose');
const Technician = require('./src/models/Technician');

async function run() {
    await mongoose.connect('mongodb://127.0.0.1:27017/dali_pfe');
    await Technician.updateOne(
        { email: 'tech.demo@dali-pfe.com' },
        { $set: { companyId: 'CLI-2026-619', machineIds: ['MAC-1775750118162'] } }
    );
    console.log('Tech updated for dzli machine');
    process.exit(0);
}

run();
