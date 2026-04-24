const mongoose = require('mongoose');
require('dotenv').config();

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/iot-monitoring';
const COMPANY_ID = '6994a5ffe606080f11eeea03'; // Enterprise Corp

const PARAMETERS = [
    { key: 'thermal', label: 'Thermal', unit: '°C', enabled: true, warnThreshold: 70, criticalThreshold: 85, icon: 'device-thermostat' },
    { key: 'pressure', label: 'Pressure', unit: 'bar', enabled: true, warnThreshold: 4, criticalThreshold: 6, icon: 'speed' },
    { key: 'power', label: 'Electricity', unit: 'A', enabled: true, warnThreshold: 40, criticalThreshold: 60, icon: 'flash-on' },
    { key: 'ultrasonic', label: 'Ultrasonic', unit: 'cm', enabled: true, warnThreshold: 20, criticalThreshold: 10, icon: 'settings-input-antenna' },
    { key: 'presence', label: 'Presence', unit: '', enabled: true, warnThreshold: null, criticalThreshold: null, icon: 'person-pin' },
    { key: 'magnetic', label: 'Magnetic', unit: 'mT', enabled: true, warnThreshold: 50, criticalThreshold: 100, icon: 'radio-button-checked' },
    { key: 'infrared', label: 'Infrared', unit: '°C', enabled: true, warnThreshold: 55, criticalThreshold: 75, icon: 'wb-sunny' },
];

async function seed() {
    console.log('🔌 Connecting to MongoDB...');
    await mongoose.connect(MONGO_URI);
    console.log('✅ Connected.');

    const Machine = require('./src/models/Machine');

    const newMachine = new Machine({
        _id: 'multi_test_01', // Custom ID for easy searching
        name: 'Machine de Surveillance Flexible',
        status: 'RUNNING',
        location: 'Ligne 01',
        companyId: new mongoose.Types.ObjectId(COMPANY_ID),
        parameters: PARAMETERS
    });

    try {
        await newMachine.save();
        console.log('✨ Success! Added machine: "Machine de Surveillance Flexible"');
        console.log('   ID:', newMachine._id);
        console.log('   Parameters:', newMachine.parameters.length, 'configured');
    } catch (err) {
        if (err.code === 11000) {
            console.log('⚠️  Machine already exists. Updating existing machine instead.');
            await Machine.findByIdAndUpdate('multi_test_01', { parameters: PARAMETERS, status: 'RUNNING' });
            console.log('✅ Parameters updated for existing machine "multi_test_01".');
        } else {
            throw err;
        }
    }

    await mongoose.disconnect();
    console.log('🔌 Disconnected.');
}

seed().catch(console.error);
