// src/models/missionModel.js
const { prisma } = require('../lib/prisma');

async function listByTechnician(technicianId, filters = {}) {
    const where = { technicianId };
    if (filters.status)   where.status   = filters.status;
    if (filters.priority) where.priority = filters.priority;
    return prisma.mission.findMany({
        where,
        orderBy: [{ priority: 'desc' }, { scheduledAt: 'asc' }],
    });
}

async function listAll(filters = {}) {
    const where = {};
    if (filters.status)      where.status      = filters.status;
    if (filters.technicianId) where.technicianId = filters.technicianId;
    if (filters.machineId)   where.machineId   = filters.machineId;
    return prisma.mission.findMany({
        where,
        orderBy: { createdAt: 'desc' },
    });
}

async function getById(id) {
    return prisma.mission.findUnique({ where: { id } });
}

async function getByMissionId(missionId) {
    return prisma.mission.findUnique({ where: { missionId } });
}

async function create(data) {
    return prisma.mission.create({ data });
}

async function update(id, data) {
    return prisma.mission.update({ where: { id }, data });
}

async function remove(id) {
    return prisma.mission.delete({ where: { id } });
}

module.exports = {
    listByTechnician,
    listAll,
    getById,
    getByMissionId,
    create,
    update,
    remove,
};
