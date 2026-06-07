const { prisma } = require('../lib/prisma');

async function findByEmail(email) {
    const emailNorm = String(email || '').trim().toLowerCase();
    return prisma.user.findUnique({ where: { email: emailNorm } });
}

async function getProfileExtras(user) {
    const r = user.role;
    if (r === 'client') {
        const p = await prisma.client.findUnique({ where: { userId: user.id } });
        return p ? { clientId: p.clientId, companyId: p.clientId } : {};
    }
    if (r === 'conception') {
        const p = await prisma.concepteur.findUnique({ where: { userId: user.id } });
        return p
            ? {
                  concepteurId: p.id,
                  companyId: p.companyId,
                  location: p.location,
                  specialite: p.specialite,
              }
            : {};
    }
    if (r === 'technician') {
        const p = await prisma.technician.findUnique({ where: { userId: user.id } });
        return p ? { technicianId: p.technicianId, companyId: p.companyId } : {};
    }
    if (r === 'maintenance') {
        const p = await prisma.maintenanceAgent.findUnique({ where: { userId: user.id } });
        return p ? { maintenanceAgentId: p.maintenanceAgentId } : {};
    }
    return {};
}

async function isClientLoginDisabled(userId) {
    const client = await prisma.client.findUnique({ where: { userId } });
    return Boolean(client?.loginDisabled);
}

async function findMaintenanceAgent(userId) {
    return prisma.maintenanceAgent.findUnique({ where: { userId } });
}

module.exports = {
    findByEmail,
    getProfileExtras,
    isClientLoginDisabled,
    findMaintenanceAgent,
};
