const { prisma } = require('../lib/prisma');
const { nextMachineId } = require('../lib/ids');

const assignedFilter = {
    companyId: { not: '' },
};

async function findMany({ catalog = false, includeAll = false, unassigned = false } = {}) {
    let where = (catalog || includeAll) ? {} : assignedFilter;
    if (unassigned) {
        where = { companyId: '' };
    }
    return prisma.machine.findMany({
        where,
        orderBy: { updatedAt: 'desc' },
    });
}

async function findManyByCompany(companyId) {
    return prisma.machine.findMany({
        where: { companyId: String(companyId) },
        orderBy: { updatedAt: 'desc' },
    });
}

async function findById(machineId) {
    return prisma.machine.findUnique({
        where: { id: String(machineId) },
    });
}

async function create(data) {
    const name = String(data.name || '').trim();
    const id = data.id || data._id || nextMachineId();
    return prisma.machine.create({
        data: {
            id: String(id),
            name,
            type: String(data.type || ''),
            companyId: String(data.companyId || ''),
            status: String(data.status || 'STOPPED'),
            motorType: String(data.motorType || 'air_cooled'),
            location: String(data.location || ''),
            disponible: data.disponible !== false,
        },
    });
}

async function updateStatus(machineId, status) {
    return prisma.machine.update({
        where: { id: String(machineId) },
        data: { status: String(status) },
    });
}

async function remove(machineId) {
    return prisma.machine.delete({
        where: { id: String(machineId) },
    });
}

module.exports = { findMany, findManyByCompany, findById, create, updateStatus, remove };
