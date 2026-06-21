const { prisma } = require('../lib/prisma');
const { nextMachineId } = require('../lib/ids');

const assignedFilter = {
    companyId: { not: '' },
};

async function findMany({ catalog = false, includeAll = false, unassigned = false, concepterId = null } = {}) {
    let where = (catalog || includeAll) ? {} : assignedFilter;
    if (unassigned) {
        where = { companyId: '' };
    }
    
    // Always filter by concepteurId if provided, so that Concepteurs only see their own machines
    if (concepterId) {
        where.concepteurId = String(concepterId);
    }
    
    // If it's a catalog view, only show public machines by default
    if (catalog && !includeAll) {
        where.isPublic = { not: false };
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
            aiType: String(data.aiType || 'M'),
            companyId: String(data.companyId || ''),
            status: String(data.status || 'STOPPED'),
            motorType: String(data.motorType || 'air_cooled'),
            location: String(data.location || ''),
            imageUrl: String(data.imageUrl || ''),
            concepteurId: String(data.concepteurId || ''),
            isPublic: data.isPublic !== false,
            disponible: data.disponible !== false,
            price: data.price !== undefined ? String(data.price) : '',
            stock: data.stock !== undefined ? parseInt(data.stock, 10) : 0,
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

async function update(machineId, data) {
    const updateData = {};
    if (data.name !== undefined) updateData.name = String(data.name).trim();
    if (data.type !== undefined) updateData.type = String(data.type);
    if (data.aiType !== undefined) updateData.aiType = String(data.aiType);
    if (data.status !== undefined) updateData.status = String(data.status);
    if (data.location !== undefined) updateData.location = String(data.location);
    if (data.imageUrl !== undefined) updateData.imageUrl = String(data.imageUrl);
    if (data.isPublic !== undefined) updateData.isPublic = !!data.isPublic;
    if (data.model3dUrl !== undefined) updateData.model3dUrl = String(data.model3dUrl);
    if (data.disponible !== undefined) updateData.disponible = !!data.disponible;
    if (data.companyId !== undefined) updateData.companyId = String(data.companyId);
    if (data.wifiSsid !== undefined) updateData.wifiSsid = String(data.wifiSsid);
    if (data.wifiPassword !== undefined) updateData.wifiPassword = String(data.wifiPassword);
    if (data.price !== undefined) updateData.price = String(data.price);
    if (data.stock !== undefined) updateData.stock = parseInt(data.stock, 10);

    return prisma.machine.update({
        where: { id: String(machineId) },
        data: updateData,
    });
}

module.exports = { findMany, findManyByCompany, findById, create, update, updateStatus, remove };
