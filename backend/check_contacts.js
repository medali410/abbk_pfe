const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
    console.log("Recherche du concepteur: lemjidmolka9@gmail.com");
    
    // 1. Trouver l'utilisateur
    const user = await prisma.user.findUnique({ where: { email: 'lemjidmolka9@gmail.com' } });
    if (!user) {
        console.log("Utilisateur introuvable.");
        return;
    }
    console.log("User:", { id: user.id, nom: user.nom });

    // 2. Trouver le profil concepteur
    const concepteur = await prisma.concepteur.findUnique({ where: { userId: user.id } });
    if (!concepteur) {
        console.log("Profil concepteur introuvable.");
        return;
    }
    console.log("Concepteur:", { id: concepteur.id, companyId: concepteur.companyId });

    // 3. Trouver ses machines
    const machines = await prisma.machine.findMany({ where: { concepteurId: String(concepteur.id) } });
    console.log(`\nMachines (${machines.length}):`, machines.map(m => m.id).join(", "));

    // 4. Trouver les techniciens, agents de maintenance et clients
    const contacts = { techs: [], agents: [], clients: [] };
    
    for (const machine of machines) {
        console.log(`\n--- Pour la machine ${machine.id} ---`);
        
        const techs = await prisma.technician.findMany({
            where: { machineIds: { contains: `"${machine.id}"` } },
            include: { user: true }
        });
        console.log("Techniciens:", techs.map(t => `${t.firstName} ${t.lastName} (${t.user.email})`));

        const agents = await prisma.maintenanceAgent.findMany({
            where: { machineIds: { contains: `"${machine.id}"` } },
            include: { user: true }
        });
        console.log("Agents de maintenance:", agents.map(a => `${a.firstName} ${a.lastName} (${a.user.email})`));

        if (machine.companyId) {
            const clients = await prisma.client.findMany({
                where: { clientId: machine.companyId },
                include: { user: true }
            });
            console.log("Clients:", clients.map(c => `${c.user.nom} (${c.user.email})`));
        }
    }
}

main().catch(console.error).finally(() => prisma.$disconnect());
