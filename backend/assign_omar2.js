const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
    try {
        console.log('Fetching technicians...');
        const technicians = await prisma.technician.findMany({ include: { user: true } });
        const omar = technicians.find(t => {
            const nom = t.user && t.user.nom ? t.user.nom.toLowerCase() : '';
            const fname = t.firstName ? t.firstName.toLowerCase() : '';
            const lname = t.lastName ? t.lastName.toLowerCase() : '';
            const tId = t.technicianId ? t.technicianId.toLowerCase() : '';
            return nom.includes('omar') || fname.includes('omar') || lname.includes('omar') || tId.includes('omar');
        });

        if (!omar) {
            console.log('Omar not found in the DB.');
            technicians.forEach(t => {
                const nom = t.user ? t.user.nom : 'NoUser';
                console.log(`- ${nom} (${t.technicianId})`);
            });
            return;
        }

        console.log(`Matched: ${omar.firstName} ${omar.lastName} | ID: ${omar.technicianId}`);

        const upd = await prisma.machine.updateMany({
            data: { technicianId: omar.technicianId }
        });
        console.log(`Machines updated: ${upd.count}`);

        const allMachines = await prisma.machine.findMany();
        for (const machine of allMachines) {
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
        console.log('Missions created.');

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
        console.log('Predictions created. DONE!');
    } catch (e) {
        console.error('ERROR:', e);
    }
}
main().finally(() => prisma.$disconnect());
