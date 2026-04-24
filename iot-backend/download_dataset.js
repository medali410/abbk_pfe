// ============================================================
//  Download ai4i2020.csv from UCI repository
// ============================================================
const https = require('https');
const fs = require('fs');
const path = require('path');

const URL = 'https://archive.ics.uci.edu/ml/machine-learning-databases/00601/ai4i2020.csv';
const DEST = path.join(__dirname, 'ai4i2020.csv');

console.log('📥 Téléchargement du dataset AI4I 2020...');
console.log('   Source:', URL);
console.log('   Destination:', DEST);

const file = fs.createWriteStream(DEST);

https.get(URL, (res) => {
    if (res.statusCode !== 200) {
        console.error('❌ Erreur HTTP:', res.statusCode);
        console.log('\n💡 Téléchargez manuellement depuis:');
        console.log('   https://www.kaggle.com/datasets/stephanmatzka/predictive-maintenance-dataset-ai4i-2020');
        console.log('   Et placez le fichier comme: ' + DEST);
        process.exit(1);
    }

    const total = parseInt(res.headers['content-length'] || 0);
    let downloaded = 0;

    res.on('data', chunk => {
        downloaded += chunk.length;
        if (total > 0) {
            const pct = ((downloaded / total) * 100).toFixed(0);
            process.stdout.write(`\r   ${pct}% (${(downloaded / 1024).toFixed(0)} KB)`);
        }
    });

    res.pipe(file);

    file.on('finish', () => {
        file.close();
        console.log('\n✅ Fichier téléchargé avec succès!');
        console.log('   Taille:', (fs.statSync(DEST).size / 1024).toFixed(1), 'KB');
        console.log('\n💡 Lancez maintenant : node import_dataset.js\n');
    });
}).on('error', (err) => {
    fs.unlink(DEST, () => { });
    console.error('❌ Erreur de téléchargement:', err.message);
    console.log('\n💡 Téléchargez manuellement depuis:');
    console.log('   https://www.kaggle.com/datasets/stephanmatzka/predictive-maintenance-dataset-ai4i-2020');
    console.log('   Ou: https://archive.ics.uci.edu/dataset/601/ai4i+2020+predictive+maintenance+dataset');
    console.log('   Et placez le fichier dans:', __dirname);
});
