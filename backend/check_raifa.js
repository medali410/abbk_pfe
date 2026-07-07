require('dotenv').config();
const { prisma } = require('./src/lib/prisma');

async function main() {
    // 1. Find Raifa user
    const users = await prisma.user.findMany({
        where: { nom: { contains: 'raifa', mode: 'insensitive' } }
    });
    console.log('=== RAIFA USERS ===');
    for (const u of users) {
        console.log('  userId:', u.id, '| nom:', u.nom, '| email:', u.email, '| role:', u.role);
    }

    // 2. All technicians with machineIds
    const techs = await prisma.technician.findMany({ include: { user: true } });
    console.log('\n=== ALL TECHNICIANS ===');
    for (const t of techs) {
        console.log('  tech.id:', t.id, '| userId:', t.userId, '| name:', t.user.nom, '| machineIds:', t.machineIds);
    }

    // 3. All machines
    const machines = await prisma.machine.findMany();
    console.log('\n=== ALL MACHINES ===');
    for (const m of machines) {
        console.log('  id:', m.id, '| name:', m.name, '| concepteurId:', m.concepteurId, '| companyId:', m.companyId);
    }

    await prisma.$disconnect();
}

main().catch(e => { console.error(e); process.exit(1); });
