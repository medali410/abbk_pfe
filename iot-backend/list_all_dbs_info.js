const mongoose = require('mongoose');

async function checkAllDbs() {
    const uri = 'mongodb://127.0.0.1:27017';
    console.log('Connexion à MongoDB...');
    
    try {
        await mongoose.connect(uri);
        const admin = mongoose.connection.useDb('admin').db;
        const dbs = await admin.admin().listDatabases();
        
        console.log('\n--- DATABASES DISPONIBLES ---');
        for (let dbObj of dbs.databases) {
            const dbName = dbObj.name;
            const size = (dbObj.sizeOnDisk / 1024 / 1024).toFixed(2);
            console.log(`- ${dbName} (${size} MB)`);
            
            // On jette un oeil aux collections dans chaque DB (sauf les systèmes)
            if (!['admin', 'config', 'local'].includes(dbName)) {
                const currentDb = mongoose.connection.useDb(dbName).db;
                const collections = await currentDb.listCollections().toArray();
                for (let coll of collections) {
                    const count = await currentDb.collection(coll.name).countDocuments();
                    console.log(`    > ${coll.name}: ${count} docs`);
                }
            }
        }

    } catch (err) {
        console.error('❌ Erreur:', err.message);
    } finally {
        await mongoose.connection.close();
        process.exit(0);
    }
}

checkAllDbs();
