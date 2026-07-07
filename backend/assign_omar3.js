const { PrismaClient } = require('@prisma/client');
const fs = require('fs');
const prisma = new PrismaClient();

async function main() {
    let out = '';
    const log = (msg) => { out += msg + '\n'; console.log(msg); };
    try {
        const technicians = await prisma.technician.findMany({ include: { user: true } });
        const omar = technicians.find(t => {
            const nom = t.user && t.user.nom ? t.user.nom.toLowerCase() : '';
            const fname = t.firstName ? t.firstName.toLowerCase() : '';
            return nom.includes('omar') || fname.includes('omar');
        });

        if (!omar) {
            log('Omar not found in DB. Available techs:');
            technicians.forEach(t => log(t.user ? t.user.nom : 'Unknown'));
        } else {
            log(`Found: ${omar.firstName} ${omar.lastName} ID: ${omar.technicianId}`);
            const upd = await prisma.machine.updateMany({ data: { technicianId: omar.technicianId } });
            log(`Machines updated: ${upd.count}`);

            const allMachines = await prisma.machine.findMany();
            if (allMachines.length > 0) {
                await prisma.mission.create({
                    data: {
                        missionId: 'MIS-OMAR-' + Date.now().toString().slice(-6),
                        technicianId: omar.technicianId,
                        machineId: allMachines[0].id,
                        machineName: allMachines[0].name,
                        title: 'Test Mission OMAR',
                        status: 'PENDING',
                        scheduledAt: new Date()
                    }
                });
                log('Mission created.');
            }
        }
    } catch (e) { log('Error: ' + e); }
    fs.writeFileSync('out_omar.txt', out);
}
main().finally(() => prisma.$disconnect());
