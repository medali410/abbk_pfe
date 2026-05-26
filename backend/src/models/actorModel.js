const { prisma } = require('../lib/prisma');

async function listConcepteurs() {
    return prisma.concepteur.findMany({ include: { user: true }, orderBy: { id: 'desc' } });
}

async function listTechnicians() {
    return prisma.technician.findMany({ include: { user: true }, orderBy: { id: 'desc' } });
}

async function listMaintenanceAgents() {
    return prisma.maintenanceAgent.findMany({
        include: { user: true },
        orderBy: { id: 'desc' },
    });
}

module.exports = { listConcepteurs, listTechnicians, listMaintenanceAgents };
