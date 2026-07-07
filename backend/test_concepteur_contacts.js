require('dotenv').config();
const { prisma } = require('./src/lib/prisma');

async function main() {
    try {
        const concepteurs = await prisma.concepteur.findMany();
        console.log('--- CONCEPTEURS ---');
        console.log(concepteurs.map(c => ({ id: c.id, userId: c.userId })));

        for (const concepteur of concepteurs) {
            console.log(`\n\n=== CONCEPTEUR ${concepteur.id} (userId: ${concepteur.userId}) ===`);
            const machines = await prisma.machine.findMany({
                where: { concepteurId: String(concepteur.id) }
            });
            console.log(`Machines associées : ${machines.length}`);
            if (machines.length > 0) {
                console.log(machines.map(m => m.id));
            }

            for (const machine of machines) {
                const techs = await prisma.technician.findMany({
                    where: {
                        OR: [
                            { machineIds: { contains: `"${machine.id}"` } },
                            ...(machine.companyId ? [{ companyId: machine.companyId }] : []),
                        ],
                    }
                });
                console.log(`\n- Machine ${machine.id} (Company ${machine.companyId}) -> Techs trouves: ${techs.length}`);
                if (techs.length > 0) {
                    console.log(techs.map(t => ({ id: t.id, name: t.firstName + ' ' + t.lastName, machineIds: t.machineIds, companyId: t.companyId })));
                }
            }
        }
    } catch (e) {
        console.error('Error:', e);
    } finally {
        await prisma.$disconnect();
    }
}
main();
