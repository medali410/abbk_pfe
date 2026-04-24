const fs = require('fs');

/**
 * Script d'analyse rapide du dataset industriel AI4I 2020
 * Objectif : Compter les pannes et identifier les corrélations de base.
 */

const fileName = 'ai4i2020.csv';

if (!fs.existsSync(fileName)) {
    console.error(`Erreur : Le fichier ${fileName} est introuvable.`);
    process.exit(1);
}

const data = fs.readFileSync(fileName, 'utf8');
const lines = data.split('\n').filter(line => line.trim() !== '');
const headers = lines[0].split(',');

const totalRecords = lines.length - 1;
let failureCount = 0;
const failureTypes = {
    TWF: 0, // Tool Wear Failure
    HDF: 0, // Heat Dissipation Failure
    PWF: 0, // Power Failure
    OSF: 0, // Overstrain Failure
    RNF: 0  // Random Failures
};

// Analyse des lignes (à partir de la linde 1)
for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(',');

    // Colonne 8 : Machine failure (0 ou 1)
    if (parseInt(cols[8]) === 1) failureCount++;

    // Colonnes 9 à 13 : Types de pannes spécifiques
    if (parseInt(cols[9]) === 1) failureTypes.TWF++;
    if (parseInt(cols[10]) === 1) failureTypes.HDF++;
    if (parseInt(cols[11]) === 1) failureTypes.PWF++;
    if (parseInt(cols[12]) === 1) failureTypes.OSF++;
    if (parseInt(cols[13]) === 1) failureTypes.RNF++;
}

console.log('====================================================');
console.log('🔍 ANALYSE DU DATASET INDUSTRIEL : AI4I 2020');
console.log('====================================================');
console.log(`📊 Total enregistrements : ${totalRecords}`);
console.log(`❌ Total des pannes détectées : ${failureCount} (${((failureCount / totalRecords) * 100).toFixed(2)}%)`);
console.log('----------------------------------------------------');
console.log('🛠️ REPARTITION PAR TYPE DE PANNE :');
console.log(`- Usure Outil (TWF)     : ${failureTypes.TWF}`);
console.log(`- Refroidissement (HDF) : ${failureTypes.HDF}`);
console.log(`- Puissance (PWF)       : ${failureTypes.PWF}`);
console.log(`- Surcharge (OSF)       : ${failureTypes.OSF}`);
console.log(`- Aléatoire (RNF)       : ${failureTypes.RNF}`);
console.log('====================================================');
console.log('💡 Conseil : Ces données sont prêtes pour entraîner un modèle.');
console.log('Vous pouvez utiliser ces stats pour équilibrer votre IA.');
