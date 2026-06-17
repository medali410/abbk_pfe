const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  console.log('Interrogation des 5 derniers enregistrements de télémétrie...');
  const telemetry = await prisma.telemetry.findMany({
    orderBy: { timestamp: 'desc' },
    take: 5
  });
  console.log(JSON.stringify(telemetry, null, 2));
}

main().catch(err => {
  console.error(err);
}).finally(async () => {
  await prisma.$disconnect();
});
