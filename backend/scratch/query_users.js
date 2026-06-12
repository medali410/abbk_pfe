const { prisma } = require('../src/lib/prisma');

async function main() {
    const users = await prisma.user.findMany({
        include: { concepteur: true, client: true, technician: true, maintenanceAgent: true }
    });
    console.log('=== USERS ===');
    console.log(JSON.stringify(users, null, 2));
}

main()
    .catch(e => console.error(e))
    .finally(async () => await prisma.$disconnect());
