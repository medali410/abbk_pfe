const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
    console.log('Fetching technicians...');
    const technicians = await prisma.technician.findMany({ include: { user: true } });
    const omar = technicians.find(t =>
        (t.firstName && t.firstName.toLowerCase().includes('omar')) ||
        (t.lastName && t.lastName.toLowerCase().includes('omar')) ||
        (t.user && t.user.nom.toLowerCase().includes('omar')) ||
        t.technicianId.toLowerCase().includes('omar')
    );

    if (!omar) {
        console.log('Omar not found in the DB. Here are the technicians:');
        technicians.forEach(t => console.log(t.user.nom, t.technicianId));
        return;
    }

    console.log(`Assigning to: ${omar.user.nom} (${omar.technicianId})`);

    // update all machines to belong to this technicianId
    await prisma.machine.updateMany({
        data: { technicianId: omar.technicianId }
    });

    console.log('Machines updated.');

    const allMachines = await prisma.machine.findMany();
    // also create some dummy missions
    for (const machine of allMachines) {
        console.log(`Creating mission for machine ${machine.id}`);
        await prisma.mission.create({
            data: {
                missionId: 'MIS-OMAR-' + Math.floor(Math.random() * 100000),
                technicianId: omar.technicianId,
                machineId: machine.id,
                machineName: machine.name,
                title: 'Inspection ' + machine.name,
                description: 'Inspection test for OMAR dashboard',
                status: 'PENDING',
                priority: 'NORMAL',
                scheduledAt: new Date(),
            }
        });
    }

    // Also create some AI analyses if missing
    for (const machine of allMachines) {
        await prisma.prediction.create({
            data: {
                machineId: machine.id,
                status: 'Critical',
                riskPercentage: 85,
                typePanne: 'Vibration excessive',
                diagnostic: 'Diagnostic IA Test Omar',
                recommandation: 'Vérifier l\'arbre',
                rulCycles: 15.5
            }
        });
    }
    console.log('DONE!');
}
main().catch(console.error).finally(() => prisma.$disconnect());
