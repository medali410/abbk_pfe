const mongoose = require('mongoose');
const Technician = require('./src/models/Technician');
const User = require('./src/models/User'); // In case some are in users table
require('dotenv').config();

async function clearTechnicians() {
    try {
        await mongoose.connect(process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/iot-monitoring');
        console.log('✅ Connected to MongoDB');

        const techResult = await Technician.deleteMany({});
        console.log(`🗑️ Removed ${techResult.deletedCount} technicians from Technician collection.`);

        // Optional: Remove users with role 'TECHNICIAN' if they exist there too
        const userResult = await User.deleteMany({ role: 'TECHNICIAN' });
        console.log(`🗑️ Removed ${userResult.deletedCount} users with role TECHNICIAN.`);

        console.log('✨ Database reset: Technicians count is now 0.');
        process.exit(0);
    } catch (err) {
        console.error('❌ Error clearing technicians:', err);
        process.exit(1);
    }
}

clearTechnicians();
