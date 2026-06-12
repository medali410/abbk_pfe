const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  const techs = await prisma.technician.findMany();
  console.log(JSON.stringify(techs, null, 2));
}

main()
  .catch(e => console.error(e))
  .finally(async () => {
    await prisma.$disconnect();
  });
