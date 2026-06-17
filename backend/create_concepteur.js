require('dotenv').config();
const { createUserWithProfile, prisma } = require('./src/lib/auth');

async function run() {
  try {
    const { user, profile } = await createUserWithProfile(
        'conception',
        { email: 'sloma4694@gmail.com', nom: 'lemjid', password: 'password123', adresse: 'Tunis' },
        {
          location: 'Tunis',
          specialite: 'Conception mécanique',
          status: 'Actif'
        }
    );
    console.log("Concepteur created successfully:", user, profile);
  } catch(e) {
    console.error("Error:", e);
  } finally {
    prisma.$disconnect();
  }
}
run();
