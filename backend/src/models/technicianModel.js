// src/models/technicianModel.js
const { prisma } = require('../lib/prisma');

/** Liste tous les techniciens avec leur profil User. */
async function listTechnicians(filters = {}) {
    const where = {};

    if (filters.status) where.status = filters.status;
    if (filters.companyId) where.companyId = filters.companyId;
    if (filters.specialization) where.specialization = filters.specialization;

    return prisma.technician.findMany({
        where,
        include: { user: true },
        orderBy: { id: 'desc' },
    });
}

/** Récupère un technicien par son id (Int) ou technicianId (String). */
async function getTechnicianByIdOrCode(id) {
    const numId = parseInt(id, 10);
    return prisma.technician.findFirst({
        where: {
            OR: [
                ...(Number.isFinite(numId) ? [{ id: numId }] : []),
                { technicianId: String(id) },
            ],
        },
        include: { user: true },
    });
}

/** Récupère un technicien par userId. */
async function getTechnicianByUserId(userId) {
    return prisma.technician.findUnique({
        where: { userId },
        include: { user: true },
    });
}

/**
 * Met à jour le profil Technician.
 * @param {number} id  – id primaire du profil Technician
 * @param {object} data – champs Technician à modifier
 */
async function updateTechnicianProfile(id, data) {
    return prisma.technician.update({ where: { id }, data });
}

/**
 * Assigne (ou retire) des machines à un technicien.
 * @param {number} id          – id primaire du profil Technician
 * @param {string[]} machineIds – tableau de IDs machines
 */
async function setMachineIds(id, machineIds) {
    return prisma.technician.update({
        where: { id },
        data: { machineIds: JSON.stringify(machineIds) },
    });
}

/** Supprime un technicien (cascade → User). */
async function deleteTechnician(userId) {
    return prisma.user.delete({ where: { id: userId } });
}

module.exports = {
    listTechnicians,
    getTechnicianByIdOrCode,
    getTechnicianByUserId,
    updateTechnicianProfile,
    setMachineIds,
    deleteTechnician,
};
