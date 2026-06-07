const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
    console.log('--- Checking DB connection ---');
    try {
        await prisma.$connect();
        console.log('Connected.');

        const machines = await prisma.machine.findMany();
        console.log(`Found ${machines.length} machines.`);

        console.log('--- Machines Details ---');
        machines.forEach(m => {
            console.log(`- ID: ${m.id}, Name: ${m.name}, isPublic: ${m.isPublic}, companyId: "${m.companyId}"`);
        });

    } catch (err) {
        console.error('ERROR:', err);
    } finally {
        await prisma.$disconnect();
    }
}

main();
