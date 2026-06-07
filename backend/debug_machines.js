const { prisma } = require('./src/lib/prisma');

async function main() {
    const machines = await prisma.machine.findMany();

    console.log('--- All Machines in DB ---');
    console.log(JSON.stringify(machines, null, 2));
}

main()
    .catch(e => console.error(e))
    .finally(async () => await prisma.$disconnect());
