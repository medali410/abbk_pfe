const { prisma } = require('./src/lib/prisma');

async function main() {
    const users = await prisma.user.findMany({ where: { role: 'conception' } });
    const concepteurs = await prisma.concepteur.findMany();

    console.log('--- Users (role=conception) ---');
    console.log(JSON.stringify(users, null, 2));

    console.log('--- Concepteurs ---');
    console.log(JSON.stringify(concepteurs, null, 2));
}

main()
    .catch(e => console.error(e))
    .finally(async () => await prisma.$disconnect());
