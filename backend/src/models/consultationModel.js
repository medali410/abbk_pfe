// src/models/consultationModel.js
const { prisma } = require('../lib/prisma');

async function listByTechnician(technicianId, filters = {}) {
    const where = { technicianId };
    if (filters.status) where.status = filters.status;
    return prisma.consultation.findMany({
        where,
        orderBy: { scheduledDate: 'asc' },
    });
}

async function listByClient(clientId) {
    return prisma.consultation.findMany({
        where: { clientId },
        orderBy: { scheduledDate: 'asc' },
    });
}

async function listByMaintenanceAgent(maintenanceAgentId) {
    return prisma.consultation.findMany({
        where: { maintenanceAgentId },
        orderBy: { scheduledDate: 'asc' },
    });
}

async function getById(id) {
    return prisma.consultation.findUnique({ where: { id } });
}

async function getByConsultationId(consultationId) {
    return prisma.consultation.findUnique({ where: { consultationId } });
}

async function create(data) {
    return prisma.consultation.create({ data });
}

async function update(id, data) {
    return prisma.consultation.update({ where: { id }, data });
}

async function remove(id) {
    return prisma.consultation.delete({ where: { id } });
}

module.exports = {
    listByTechnician,
    listByClient,
    listByMaintenanceAgent,
    getById,
    getByConsultationId,
    create,
    update,
    remove,
};
