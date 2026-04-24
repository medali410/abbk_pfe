const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/abbk_iot';

async function check() {
    await mongoose.connect(MONGO_URI);
    const Telemetry = mongoose.model('Telemetry', new mongoose.Schema({}, { strict: false }));
    const latest = await Telemetry.findOne({ machineId: 'MAC_A01' }).sort({ timestamp: -1 });
    console.log('Latest Telemetry:', latest);
    process.exit(0);
}

check();
