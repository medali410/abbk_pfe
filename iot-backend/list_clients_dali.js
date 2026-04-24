const mongoose = require('mongoose');

async function listClients() {
    const uri = 'mongodb://127.0.0.1:27017/dali_pfe';
    console.log('Connexion à MongoDB (dali_pfe)...');
    
    try {
        await mongoose.connect(uri);
        console.log('✅ Connecté.');

        // On interroge directement la collection "clients"
        const db = mongoose.connection.db;
        const clients = await db.collection('clients').find({}).toArray();

        console.log('\n--- LISTE DES CLIENTS ---');
        if (clients.length === 0) {
            console.log('Aucun client trouvé.');
        } else {
            clients.forEach(c => {
                console.log(`- [${c.clientId || c._id}] Name: ${c.name}, Email: ${c.email}, Machines: ${c.machines || 0}`);
            });
        }

        // On vérifie aussi les utilisateurs (SuperAdmins / Techniciens)
        const users = await db.collection('users').find({}).toArray();
        console.log('\n--- LISTE DES UTILISATEURS ---');
        if (users.length === 0) {
            console.log('Aucun utilisateur trouvé.');
        } else {
            users.forEach(u => {
                console.log(`- [${u.role}] Name: ${u.name}, Email: ${u.email}`);
            });
        }

    } catch (err) {
        console.error('❌ Erreur:', err.message);
    } finally {
        await mongoose.connection.close();
        process.exit(0);
    }
}

listClients();
