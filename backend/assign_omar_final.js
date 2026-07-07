const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
    const technicians = await prisma.technician.findMany({ include: { user: true } });
    const omar = technicians.find(t => (t.user && t.user.nom.toLowerCase().includes('omar')) || (t.firstName && t.firstName.toLowerCase().includes('omar')));
    if (!omar) {
        console.log("Omar not found");
        return;
    }

    const machines = await prisma.machine.findMany();
    const machineIds = machines.map(m => m.id);

    await prisma.technician.update({
        where: { id: omar.id },
        data: { machineIds: machineIds }
    });

    await prisma.machine.updateMany({
        data: { technicianId: omar.technicianId }
    });
    console.log("Done updating arrays.");
}
main().catch(console.error).finally(() => prisma.$disconnect());
