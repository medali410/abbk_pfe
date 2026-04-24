const mongoose = require('mongoose');
const User = require('./src/models/User');
const Machine = require('./src/models/Machine');
const Telemetry = require('./src/models/Telemetry');
const Company = require('./src/models/Company');
require('dotenv').config();

const seedData = async () => {
    try {
        await mongoose.connect(process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/iot-monitoring');
        console.log('MongoDB Connected for Seeding');

        // Clear existing data
        await User.deleteMany({});
        await Machine.deleteMany({});
        await Telemetry.deleteMany({});
        await Company.deleteMany({});
        console.log('Cleared existing data');

        // Create Companies
        const companies = await Company.create([
            { name: 'rfghj', address: '789 Test St', logo: 'https://placehold.co/100x100?text=RF' },
            { name: 'Industrial Dev', address: '123 Factory St', logo: 'https://placehold.co/100x100?text=ID' },
            { name: 'Enterprise Corp', address: '456 Business Ave', logo: 'https://placehold.co/100x100?text=EC' },
        ]);
        console.log('Companies created:', companies.length);

        // Create Users
        const users = await User.create([
            {
                email: 'admin',
                username: 'admin',
                password: 'admin',
                role: 'SUPER_ADMIN'
            },
            {
                email: 'company@enterprise.com',
                username: 'company',
                password: 'password123',
                role: 'COMPANY_ADMIN',
                companyId: companies[1]._id
            },
            {
                email: 'marie@enterprise.com',
                username: 'marie',
                password: 'password123',
                role: 'COMPANY_ADMIN',
                companyId: companies[1]._id
            },
            {
                email: 'jean@enterprise.com',
                username: 'jean',
                password: 'password123',
                role: 'TECHNICIAN',
                companyId: companies[1]._id
            },
        ]);
        console.log('Users created:', users.length);

        // Create Machines
        const machines = await Machine.create([
            {
                _id: 'MAC_RF_01',
                name: 'Machine de Verification',
                status: 'RUNNING',
                location: 'Zone Test rfghj',
                lastMaintenance: new Date(),
                companyId: companies[0]._id
            },
            {
                _id: 'MAC_A01',
                name: 'Ligne Production A',
                status: 'RUNNING',
                location: 'Atelier 1 - Zone Nord',
                lastMaintenance: new Date('2023-10-15'),
                companyId: companies[2]._id
            },
            {
                _id: 'MAC_B02',
                name: 'Compresseur B2',
                status: 'STOPPED',
                location: 'Atelier 2 - Zone Est',
                lastMaintenance: new Date('2023-11-01'),
                companyId: companies[1]._id
            },
            {
                _id: 'MAC_C03',
                name: 'Pompe Hydraulique C',
                status: 'MAINTENANCE',
                location: 'Atelier 1 - Zone Sud',
                lastMaintenance: new Date('2023-12-10'),
                companyId: companies[1]._id
            },
            {
                _id: 'MAC_D01',
                name: 'Convoyeur D1',
                status: 'RUNNING',
                location: 'Atelier 3 - Zone Ouest',
                lastMaintenance: new Date('2023-09-20'),
                companyId: companies[1]._id
            }
        ]);
        console.log('Machines created:', machines.length);

        // Create Telemetry for each machine
        const telemetryDocs = [];
        for (const machine of machines) {
            // Generate 10 mock readings for history
            for (let i = 0; i < 10; i++) {
                const temp = 40 + Math.random() * 30;
                const vib = Math.random() * 5;
                const pow = 10 + Math.random() * 10;
                const prox = 50 + Math.random() * 50;
                telemetryDocs.push({
                    machineId: machine._id,
                    temperature: temp,
                    vibration: vib,
                    powerConsumption: pow,
                    proximity: prox,
                    metrics: {
                        thermal: temp,
                        vibration: vib,
                        power: pow,
                        ultrasonic: prox,
                        pressure: 1 + Math.random() * 200,
                        magnetic: 10 + Math.random() * 40,
                        infrared: 30 + Math.random() * 30,
                        presence: Math.random() > 0.5 ? 1 : 0
                    },
                    createdAt: new Date(Date.now() - i * 3000), // Spaced by 3 seconds
                });
            }
        }
        await Telemetry.insertMany(telemetryDocs);
        console.log('Telemetry created:', telemetryDocs.length);

        console.log('Seeding Completed Successfully');
        process.exit(0);
    } catch (error) {
        console.error('Seeding Error:', error);
        process.exit(1);
    }
};

seedData();
