// src/controllers/controleController.js
const { prisma } = require('../lib/prisma');

async function getControles(req, res) {
    try {
        const { days } = req.query;
        let dateFilter = {};
        if (days) {
            const dateLimit = new Date();
            dateLimit.setDate(dateLimit.getDate() - parseInt(days, 10));
            dateFilter = { createdAt: { gte: dateLimit } };
        }

        const controles = await prisma.controle.findMany({
            where: dateFilter,
            orderBy: { createdAt: 'desc' },
            include: { machine: { select: { id: true, name: true, type: true } } },
        });

        const agents = await prisma.maintenanceAgent.findMany({
            include: { user: { select: { nom: true } } }
        });

        const results = controles.map(c => {
            const agent = agents.find(a => {
                try {
                    const ids = JSON.parse(a.machineIds || '[]');
                    return ids.includes(c.machineId);
                } catch (_) {
                    return false;
                }
            });
            return {
                ...c,
                maintenanceAgentNom: agent ? (agent.user?.nom || `${agent.firstName} ${agent.lastName}`) : 'ons hammami'
            };
        });

        return res.json(results);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getControlesForMachine(req, res) {
    try {
        const { id } = req.params;
        const controles = await prisma.controle.findMany({
            where: { machineId: id },
            orderBy: { createdAt: 'desc' },
            include: { machine: { select: { id: true, name: true } } },
        });

        const agents = await prisma.maintenanceAgent.findMany({
            include: { user: { select: { nom: true } } }
        });

        const results = controles.map(c => {
            const agent = agents.find(a => {
                try {
                    const ids = JSON.parse(a.machineIds || '[]');
                    return ids.includes(c.machineId);
                } catch (_) {
                    return false;
                }
            });
            return {
                ...c,
                maintenanceAgentNom: agent ? (agent.user?.nom || `${agent.firstName} ${agent.lastName}`) : 'ons hammami'
            };
        });

        return res.json(results);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getControlesForTechnician(req, res) {
    try {
        const { id } = req.params; // technicienId
        const { days } = req.query;

        let dateFilter = {};
        if (days) {
            const dateLimit = new Date();
            dateLimit.setDate(dateLimit.getDate() - parseInt(days, 10));
            dateFilter = { createdAt: { gte: dateLimit } };
        }

        const controles = await prisma.controle.findMany({
            where: { technicienId: id, ...dateFilter },
            orderBy: { createdAt: 'desc' },
            include: { machine: { select: { id: true, name: true, type: true, status: true } } },
        });

        // Appending machineId directly on objects for easier flutter parsing, though included
        const results = controles.map(c => ({
            ...c,
            machineName: c.machine?.name,
            machineType: c.machine?.type,
        }));

        return res.json(results);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function submitControleCalendrierSaisie(req, res) {
    try {
        const { machineId, jour, compteRendu, technicienId, technicienNom } = req.body;

        if (!machineId || !jour) {
            return res.status(400).json({ error: 'machineId et jour sont requis' });
        }

        const newControle = await prisma.controle.create({
            data: {
                machineId,
                jour,
                compteRendu: compteRendu || '',
                technicienId: technicienId || '',
                technicienNom: technicienNom || '',
                statut: 'TERMINE',
                type: 'TERRAIN',
            },
        });

        const io = req.app.get('io');
        if (io) {
            io.emit('controle_notification', {
                machineId,
                title: 'Nouveau Contrôle',
                body: `Un contrôle a été effectué par ${technicienNom || 'un technicien'}.`,
                controle: newControle,
            });
        }

        return res.status(201).json(newControle);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getControlCalendrierJournal(req, res) {
    try {
        const { machineId, limit } = req.query;
        if (!machineId) return res.status(400).json({ error: 'machineId requis' });

        const take = limit ? parseInt(limit, 10) : 50;

        const controles = await prisma.controle.findMany({
            where: { machineId },
            take,
            orderBy: { createdAt: 'desc' },
        });

        return res.json(controles);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function updateControleStatus(req, res) {
    try {
        const { id } = req.params;
        const { statut, notes, technicienId } = req.body;

        const data = { statut };
        if (notes !== undefined) data.notes = notes;
        if (technicienId !== undefined) data.technicienId = technicienId;

        const updated = await prisma.controle.update({
            where: { id: parseInt(id, 10) },
            data,
        });

        if (statut === 'TERMINE') {
            const io = req.app.get('io');
            if (io) {
                io.emit('controle_notification', {
                    machineId: updated.machineId,
                    title: 'Contrôle Terminé',
                    body: `Le statut du contrôle a été mis à jour à TERMINE.`,
                    controle: updated,
                });
            }
        }

        return res.json(updated);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function assignControleToTechnician(req, res) {
    try {
        const { id } = req.params;
        const { technicienId } = req.body;

        const updated = await prisma.controle.update({
            where: { id: parseInt(id, 10) },
            data: { technicienId },
        });

        return res.json(updated);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getPreventiveHistory(req, res) {
    try {
        const { machineId, technicienId } = req.query;
        
        const where = { type: 'PREVENTIF' };
        if (machineId) where.machineId = machineId;
        if (technicienId) where.technicienId = technicienId;

        const history = await prisma.controle.findMany({
            where,
            orderBy: { createdAt: 'desc' },
            include: { machine: { select: { id: true, name: true } } },
        });

        return res.json(history);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = {
    getControles,
    getControlesForMachine,
    getControlesForTechnician,
    submitControleCalendrierSaisie,
    getControlCalendrierJournal,
    updateControleStatus,
    assignControleToTechnician,
    getPreventiveHistory,
};
