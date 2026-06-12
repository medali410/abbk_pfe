// src/models/maintenanceAgentModel.js
const { prisma } = require('../lib/prisma');

/** Liste tous les agents de maintenance avec leur profil User. */
async function listMaintenanceAgents(filters = {}) {
    const where = {};
    if (filters.clientId) where.clientId = filters.clientId;

    return prisma.maintenanceAgent.findMany({
        where,
        include: { user: true },
        orderBy: { id: 'desc' },
    });
}

/** Récupère un agent par son id (Int) ou maintenanceAgentId (String). */
async function getAgentByIdOrCode(id) {
    const numId = parseInt(id, 10);
    return prisma.maintenanceAgent.findFirst({
        where: {
            OR: [
                ...(Number.isFinite(numId) ? [{ id: numId }] : []),
                { maintenanceAgentId: String(id) },
            ],
        },
        include: { user: true },
    });
}

/** Récupère un agent par userId. */
async function getAgentByUserId(userId) {
    return prisma.maintenanceAgent.findUnique({
        where: { userId },
        include: { user: true },
    });
}

/**
 * Met à jour le profil MaintenanceAgent.
 * @param {number} id   – id primaire du profil
 * @param {object} data – champs à modifier
 */
async function updateAgentProfile(id, data) {
    return prisma.maintenanceAgent.update({ where: { id }, data });
}

/**
 * Assigne (ou retire) des machines à un agent.
 * @param {number} id          – id primaire du profil
 * @param {string[]} machineIds – tableau de IDs machines
 */
async function setMachineIds(id, machineIds) {
    return prisma.maintenanceAgent.update({
        where: { id },
        data: { machineIds: JSON.stringify(machineIds) },
    });
}

/** Supprime un agent de maintenance (cascade → User). */
async function deleteAgent(userId) {
    return prisma.user.delete({ where: { id: userId } });
}

module.exports = {
    listMaintenanceAgents,
    getAgentByIdOrCode,
    getAgentByUserId,
    updateAgentProfile,
    setMachineIds,
    deleteAgent,
};
