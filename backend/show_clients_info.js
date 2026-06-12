const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  const clients = await prisma.client.findMany({
    include: {
      user: true,
    },
  });

  console.log("=== Clients in Database ===\n");
  for (const client of clients) {
    console.log(`- ID (Système): ${client.id}`);
    console.log(`- ID Client: ${client.clientId}`);
    console.log(`- Nom: ${client.user?.nom}`);
    console.log(`- Email: ${client.user?.email}`);
    console.log(`- Adresse: ${client.user?.adresse}`);
    console.log(`- Localisation: ${client.location}`);
    console.log(`- Type de moteur: ${client.motorType}`);
    
    // Machines
    const machines = await prisma.machine.findMany({
        where: { companyId: client.clientId }
    });
    console.log(`- Machines (${machines.length}): ${machines.map(m => m.name).join(', ')}`);

    // Technicians
    const technicians = await prisma.technician.findMany({
        where: { companyId: client.clientId },
        include: { user: true }
    });
    console.log(`- Techniciens (${technicians.length}): ${technicians.map(t => t.user?.nom).join(', ')}`);

    // Maintenance Agents
    const maintenanceAgents = await prisma.maintenanceAgent.findMany({
        where: { clientId: client.clientId },
        include: { user: true }
    });
    console.log(`- Agents de maintenance (${maintenanceAgents.length}): ${maintenanceAgents.map(a => a.user?.nom).join(', ')}`);
    console.log("--------------------------------------------------\n");
  }
}

main()
  .catch(e => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
