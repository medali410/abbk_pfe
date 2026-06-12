const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function checkUser() {
  const u = await prisma.user.findUnique({where: {email: 'hakim40@gmail.com'}, include: {client: true}});
  console.log('User:', u);
}

checkUser().finally(() => prisma.$disconnect());
