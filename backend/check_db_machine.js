const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  console.log('Interrogation des machines enregistrées...');
  const machines = await prisma.machine.findMany();
  machines.forEach(m => {
    console.log(`- ID: ${m.id} | Nom: ${m.name} | MotorType: ${m.motorType} | ClientId: ${m.clientId}`);
  });
}

main().catch(err => {
  console.error(err);
}).finally(async () => {
  await prisma.$disconnect();
});
