// src/controllers/maintenanceOrderController.js
const { prisma } = require('../lib/prisma');

async function getMaintenanceOrders(req, res) {
    try {
        const { machineId } = req.query;
        let where = {};
        if (machineId) {
            where.machineId = machineId;
        }

        const orders = await prisma.maintenanceOrder.findMany({
            where,
            orderBy: { createdAt: 'desc' },
            include: { machine: { select: { id: true, name: true } } },
        });

        return res.json(orders);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function createMaintenanceOrder(req, res) {
    try {
        const { machineId, description, technicianId, technicianName } = req.body;

        if (!machineId || !description) {
            return res.status(400).json({ error: 'machineId et description sont requis' });
        }

        const newOrder = await prisma.maintenanceOrder.create({
            data: {
                machineId,
                description,
                technicianId: technicianId || '',
                technicianName: technicianName || '',
                status: 'PENDING',
            },
        });

        return res.status(201).json(newOrder);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function updateMaintenanceOrder(req, res) {
    try {
        const { id } = req.params;
        const { description, technicianId, technicianName, status } = req.body;

        const data = {};
        if (description !== undefined) data.description = description;
        if (technicianId !== undefined) data.technicianId = technicianId;
        if (technicianName !== undefined) data.technicianName = technicianName;
        if (status !== undefined) data.status = status;

        const updated = await prisma.maintenanceOrder.update({
            where: { id },
            data,
        });

        return res.json(updated);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function updateMaintenanceOrderStatus(req, res) {
    try {
        const { id } = req.params;
        const { status } = req.body;

        if (!status) {
            return res.status(400).json({ error: 'status est requis' });
        }

        const updated = await prisma.maintenanceOrder.update({
            where: { id },
            data: { status },
        });

        return res.json(updated);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = {
    getMaintenanceOrders,
    createMaintenanceOrder,
    updateMaintenanceOrder,
    updateMaintenanceOrderStatus,
};
