/**
 * Réinitialise le mot de passe d'un client (collection clients).
 * Usage: node reset_client_password.js <email> <nouveau_mot_de_passe>
 *
 * Exemple:
 *   node reset_client_password.js mahmoud@gmail.com 123456
 */
require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const Client = require('./src/models/Client');

const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe';

async function main() {
    const email = (process.argv[2] || '').trim().toLowerCase();
    const plain = process.argv[3] || '';
    if (!email.includes('@') || plain.length < 1) {
        console.error('Usage: node reset_client_password.js <email> <nouveau_mot_de_passe>');
        process.exit(1);
    }
    await mongoose.connect(uri, { serverSelectionTimeoutMS: 8000 });
    const hash = await bcrypt.hash(plain, 10);
    const res = await Client.updateOne({ email }, { $set: { password: hash } });
    if (res.matchedCount === 0) {
        const alt = await Client.findOne({
            email: new RegExp(`^${email.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i'),
        });
        if (alt) {
            await Client.updateOne({ _id: alt._id }, { $set: { password: hash } });
            console.log('OK — mot de passe mis à jour pour:', alt.email);
        } else {
            console.error('Aucun client trouvé avec cet email:', email);
            process.exit(2);
        }
    } else {
        console.log('OK — mot de passe mis à jour pour:', email);
    }
    await mongoose.disconnect();
}

main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
});
