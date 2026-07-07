const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
    const machines = await prisma.machine.findMany();
    const machineIds = machines.map(m => m.id);

    const technicians = await prisma.technician.findMany();
    for (const tech of technicians) {
        await prisma.technician.update({
            where: { id: tech.id },
            data: { machineIds: machineIds } // Ensure backward compatibility array
        });
    }

    const agents = await prisma.maintenanceAgent.findMany();
    for (const agent of agents) {
        await prisma.maintenanceAgent.update({
            where: { id: agent.id },
            data: { assignedMachines: machineIds } // Ensure array is populated
        });
    }

    console.log("Success: Assigned all machines to all technical profiles!");
}
main().catch(console.error).finally(() => prisma.$disconnect());
