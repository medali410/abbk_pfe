const mongoose = require('mongoose');
const Telemetry = require('./src/models/Telemetry');
require('dotenv').config();

const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/iot-monitoring';

mongoose.connect(MONGO_URI)
    .then(async () => {
        console.log('Connected to MongoDB');
        const latest = await Telemetry.findOne({ machineId: 'MAC_A01' }).sort({ createdAt: -1 });
        if (latest) {
            console.log('--- LATEST TELEMETRY FOR MAC_A01 ---');
            console.log(`Timestamp: ${latest.createdAt}`);
            console.log(`Metrics: ${JSON.stringify(latest.metrics, null, 2)}`);

            const diff = Date.now() - new Date(latest.createdAt).getTime();
            console.log(`Seconds since last update: ${Math.round(diff / 1000)}s`);
        } else {
            console.log('No telemetry found for MAC_A01');
        }
        process.exit();
    })
    .catch(err => {
        console.error('Connection Error:', err);
        process.exit(1);
    });
