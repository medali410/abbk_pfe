require('dotenv').config();
const { createUserWithProfile, prisma } = require('./src/lib/auth');

async function run() {
  try {
    const { user, profile } = await createUserWithProfile(
        'maintenance',
        { email: 'lemjiddali341@gmail.com', nom: 'helmi aa', password: 'password123', adresse: 'kelibia' },
        { 
            firstName: 'helmi', 
            lastName: 'aa', 
            clientId: 'CLI-A81DF6',
            machineIds: '[]'
        }
    );
    console.log("Created successfully:", user, profile);
  } catch(e) {
    console.error("Error:", e);
  } finally {
    prisma.$disconnect();
  }
}
run();
