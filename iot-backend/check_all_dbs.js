const mongoose = require('mongoose');

async function check(dbName) {
    const uri = `mongodb://localhost:27017/${dbName}`;
    console.log(`Checking ${dbName}...`);
    try {
        const conn = await mongoose.createConnection(uri).asPromise();
        const Telemetry = conn.model('Telemetry', new mongoose.Schema({}, { strict: false }));
        const latest = await Telemetry.findOne({ machineId: 'MAC_A01' }).sort({ timestamp: -1 });
        if (latest) {
            console.log(`Latest in ${dbName}:`, latest.timestamp, latest._id);
        } else {
            console.log(`No telemetry in ${dbName}`);
        }
        await conn.close();
    } catch (e) {
        console.error(`Error checking ${dbName}:`, e.message);
    }
}

async function run() {
    await check('abbka');
    await check('iot-monitoring');
    await check('abbk_iot');
    process.exit(0);
}

run();
