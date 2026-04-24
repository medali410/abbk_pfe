const mongoose = require('mongoose');
const User = require('./src/models/User');
const Machine = require('./src/models/Machine');
const Company = require('./src/models/Company');
const Client = require('./src/models/Client');
require('dotenv').config();

const seedForUser = async () => {
    try {
        await mongoose.connect(process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe');
        console.log('✅ Connecté à dali_pfe pour le seed');

        // 1. Créer une entreprise par défaut si nécessaire
        let defaultCompany = await Company.findOne({ name: 'Dali Industry' });
        if (!defaultCompany) {
            defaultCompany = await Company.create({
                name: 'Dali Industry',
                address: 'Sousse, Tunisie',
                logo: 'https://placehold.co/100x100?text=DI'
            });
            console.log('✅ Entreprise créée');
        }

        // 2. Créer l'admin
        const adminEmail = 'admin';
        const existingAdmin = await User.findOne({ username: 'admin' });
        if (!existingAdmin) {
            await User.create({
                email: 'admin@dali-pfe.com',
                username: 'admin',
                password: 'admin',
                role: 'SUPER_ADMIN'
            });
            console.log('✅ Admin créé (admin / admin)');
        }

        // 3. Créer la machine hatha
        const machineId = 'MAC-1775584422177';
        const existingMachine = await Machine.findById(machineId);
        if (!existingMachine) {
            await Machine.create({
                _id: machineId,
                name: 'hatha (Machine MQTT)',
                status: 'RUNNING',
                location: 'Zone A-01',
                companyId: defaultCompany._id,
                lastMaintenance: new Date()
            });
            console.log(`✅ Machine ${machineId} créée`);
        }

        console.log('🚀 Seed terminé avec succès !');
        process.exit(0);
    } catch (err) {
        console.error('❌ Erreur Seed:', err.message);
        process.exit(1);
    }
};

seedForUser();
