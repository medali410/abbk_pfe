const { prisma } = require('../src/lib/prisma');

async function main() {
    const prs = await prisma.purchaseRequest.findMany({
        orderBy: { createdAt: 'desc' }
    });
    const machines = await prisma.machine.findMany();

    console.log('=== PURCHASE REQUESTS ===');
    console.log(JSON.stringify(prs, null, 2));

    console.log('=== MACHINES ===');
    console.log(JSON.stringify(machines, null, 2));
}

main()
    .catch(e => console.error(e))
    .finally(async () => await prisma.$disconnect());
