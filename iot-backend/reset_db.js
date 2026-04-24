const mongoose = require('mongoose');
require('dotenv').config();

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/iot-monitoring';

const DEFAULT_PARAMETERS = [
    { key: 'thermal', label: 'Température', unit: '°C', enabled: true, warnThreshold: 70, criticalThreshold: 85, icon: 'device-thermostat' },
    { key: 'pressure', label: 'Pression', unit: 'bar', enabled: false, warnThreshold: 3, criticalThreshold: 5, icon: 'speed' },
    { key: 'power', label: 'Puissance', unit: 'A', enabled: false, warnThreshold: 50, criticalThreshold: 80, icon: 'flash-on' },
    { key: 'ultrasonic', label: 'Ultrason', unit: 'cm', enabled: false, warnThreshold: 20, criticalThreshold: 10, icon: 'settings-input-antenna' },
    { key: 'presence', label: 'Présence', unit: '', enabled: false, warnThreshold: null, criticalThreshold: null, icon: 'person-pin' },
    { key: 'magnetic', label: 'Magnétique', unit: 'mT', enabled: false, warnThreshold: 50, criticalThreshold: 100, icon: 'radio-button-checked' },
    { key: 'infrared', label: 'Infrarouge', unit: '°C', enabled: false, warnThreshold: 60, criticalThreshold: 80, icon: 'wb-sunny' },
];

async function reset() {
    console.log('🔌 Connexion à MongoDB...');
    await mongoose.connect(MONGO_URI);
    console.log('✅ Connecté.');

    console.log('🗑️ Suppression de la base de données...');
    await mongoose.connection.dropDatabase();
    console.log('✅ Base de données supprimée.');

    const Company = require('./src/models/Company');
    const User = require('./src/models/User');
    const Machine = require('./src/models/Machine');

    // 1. Create Company
    console.log('🏢 Création de l\'entreprise...');
    const company = new Company({
        name: 'Industrial Solutions',
        address: 'Zone Industrielle Nord, Secteur A',
        logo: 'https://placehold.co/100x100?text=IS'
    });
    await company.save();
    console.log('✅ Entreprise créée:', company.name);

    // 2. Create Users
    console.log('👤 Création des utilisateurs...');
    const users = [
        {
            email: 'admin@monitor.com',
            username: 'admin',
            password: 'password123',
            role: 'SUPER_ADMIN'
        },
        {
            email: 'marie@industrial.com',
            username: 'marie',
            password: 'password123',
            role: 'COMPANY_ADMIN',
            companyId: company._id.toString()
        },
        {
            email: 'tech@industrial.com',
            username: 'tech',
            password: 'password123',
            role: 'TECHNICIAN',
            companyId: company._id.toString()
        }
    ];

    for (const u of users) {
        await new User(u).save();
    }
    console.log('✅ Utilisateurs créés (admin, marie, tech).');

    // 3. Create Machines
    console.log('🏗️ Création des machines...');
    const machines = [
        { _id: 'presse_01', name: 'Presse Hydraulique A', location: 'Atelier 1', companyId: company._id, status: 'RUNNING', parameters: DEFAULT_PARAMETERS },
        { _id: 'four_01', name: 'Four Industriel B', location: 'Atelier 2', companyId: company._id, status: 'RUNNING', parameters: DEFAULT_PARAMETERS },
        { _id: 'rob_01', name: 'Robot Soudure C', location: 'Atelier 1', companyId: company._id, status: 'STOPPED', parameters: DEFAULT_PARAMETERS },
        { _id: 'conv_01', name: 'Convoyeur D', location: 'Atelier 3', companyId: company._id, status: 'RUNNING', parameters: DEFAULT_PARAMETERS },
    ];

    for (const m of machines) {
        await new Machine(m).save();
    }
    console.log('✅ Machines créées.');

    await mongoose.disconnect();
    console.log('\n✨ Database réinitialisée avec succès !');
    console.log('📧 Login admin: admin@monitor.com / password123');
    console.log('📧 Login marie: marie@industrial.com / password123');
}

reset().catch(err => {
    console.error('❌ Erreur:', err);
    process.exit(1);
});
