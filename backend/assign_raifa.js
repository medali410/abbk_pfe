const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
    console.log('Fetching technicians...');
    const technicians = await prisma.technician.findMany({ include: { user: true } });
    const raifa = technicians.find(t =>
        (t.firstName && t.firstName.toLowerCase().includes('raifa')) ||
        (t.lastName && t.lastName.toLowerCase().includes('raifa')) ||
        (t.user && t.user.nom.toLowerCase().includes('raifa'))
    );

    let techToAssign = raifa || technicians[0];
    if (!techToAssign) {
        console.log('No technicians found.');
        return;
    }

    console.log(`Assigning to: ${techToAssign.firstName} ${techToAssign.lastName} (${techToAssign.technicianId})`);

    // update all machines to belong to this technicianId
    await prisma.machine.updateMany({
        data: { technicianId: techToAssign.technicianId }
    });

    console.log('Machines updated.');

    const allMachines = await prisma.machine.findMany();
    // also create some dummy missions
    for (const machine of allMachines.slice(0, 3)) {
        console.log(`Creating mission for machine ${machine.id}`);
        await prisma.mission.create({
            data: {
                missionId: 'MIS-TEST-' + Math.floor(Math.random() * 10000),
                technicianId: techToAssign.technicianId,
                machineId: machine.id,
                machineName: machine.name,
                title: 'Inspection ' + machine.name,
                description: 'Inspection test for RAIFA dashboard',
                status: 'PENDING',
                priority: 'NORMAL',
                scheduledAt: new Date(),
            }
        });
    }
    console.log('Missions created.');

    // Also create some AI analyses if missing
    for (const machine of allMachines.slice(0, 3)) {
        await prisma.prediction.create({
            data: {
                machineId: machine.id,
                status: 'Critical',
                riskPercentage: 85,
                typePanne: 'Vibration excessive',
                diagnostic: 'Diagnostic IA Test',
                recommandation: 'Vérifier l\'arbre',
                rulCycles: 15.5
            }
        });
    }
    console.log('Predictions created.');
}
main().catch(console.error).finally(() => prisma.$disconnect());
