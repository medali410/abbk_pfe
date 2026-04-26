const mongoose = require('mongoose');
const Machine = require('./src/models/Machine');
require('dotenv').config();

async function check() {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/dali_pfe');
    const m = await Machine.findOne({ _id: 'MAC-1775750118162' });
    if (m) console.log('Name:', m.name);
    else console.log('Machine not found');
    await mongoose.disconnect();
}
check();
