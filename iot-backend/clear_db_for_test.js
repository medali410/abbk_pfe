const mongoose = require('mongoose');
const dotenv = require('dotenv');
const path = require('path');

dotenv.config();

// Define models locally to avoid path issues if needed, but let's try importing
const DiagnosticIntervention = require('./src/models/DiagnosticIntervention');
const MaintenanceOrder = require('./src/models/MaintenanceOrder');
const Machine = require('./src/models/Machine');

async function clear() {
    const atlasUri = process.env.MONGO_URI;
    const localUri = 'mongodb://127.0.0.1:27017/dali_pfe';
    
    let connected = false;
    if (atlasUri) {
        console.log('⏳ Connecting to MongoDB Atlas...');
        try {
            await mongoose.connect(atlasUri, { serverSelectionTimeoutMS: 5000 });
            console.log('✅ MongoDB Atlas connected');
            connected = true;
        } catch (err) {
            console.error('❌ Atlas failed:', err.message);
        }
    }

    if (!connected) {
        console.log('⏳ Connecting to MongoDB Local...');
        try {
            await mongoose.connect(localUri, { serverSelectionTimeoutMS: 5000 });
            console.log('✅ MongoDB Local connected');
            connected = true;
        } catch (err) {
            console.error('❌ Local failed:', err.message);
        }
    }

    if (!connected) {
        console.error('❌ Could not connect to any database.');
        process.exit(1);
    }
    
    console.log('Clearing DiagnosticInterventions...');
    const resDI = await DiagnosticIntervention.deleteMany({});
    console.log(`Deleted ${resDI.deletedCount} interventions.`);
    
    console.log('Clearing MaintenanceOrders...');
    const resMO = await MaintenanceOrder.deleteMany({});
    console.log(`Deleted ${resMO.deletedCount} orders.`);
    
    console.log('Resetting Machine maintenance states...');
    const resM = await Machine.updateMany({}, {
        maintenanceControlActive: false,
        maintenanceControlBy: null,
        maintenanceControlStartedAt: null,
        maintenanceControlEndsAt: null,
        status: 'RUNNING'
    });
    console.log(`Reset ${resM.modifiedCount} machines.`);
    
    console.log('Database cleared and machines reset (State 0).');
    mongoose.connection.close();
}

clear().catch(err => {
    console.error('Error clearing database:', err);
    process.exit(1);
});
