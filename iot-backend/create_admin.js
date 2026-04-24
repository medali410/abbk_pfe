require('dotenv').config();
const mongoose = require('mongoose');

const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/iot-monitoring';

const UserSchema = new mongoose.Schema({
  email: String,
  username: String,
  password: String,
  role: String,
}, { timestamps: true });

const User = mongoose.model('User', UserSchema);

async function createAdmin() {
  await mongoose.connect(MONGO_URI);
  console.log('✅ Connecté à MongoDB');

  // Supprimer l'ancien admin si existe
  await User.deleteOne({ username: 'admin' });

  // Créer le nouvel admin
  const admin = new User({
    email: 'admin@admin.com',
    username: 'admin',
    password: 'admin',  // en clair (pas de hachage pour l'instant)
    role: 'SUPER_ADMIN',
  });

  await admin.save();
  console.log('✅ Utilisateur admin créé : username=admin / password=admin');
  await mongoose.disconnect();
  process.exit(0);
}

createAdmin().catch(err => {
  console.error('❌ Erreur:', err);
  process.exit(1);
});
