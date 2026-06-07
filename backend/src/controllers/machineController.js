const MachineModel = require('../models/machineModel');
const { serializeMachine } = require('../views/machineView');

async function list(req, res) {
    try {
        const catalog = String(req.query.catalog || '') === '1';
        const includeAll = String(req.query.includeAllMongo || '') === '1';
        const unassigned = String(req.query.unassigned || '') === '1';
        const concepterId = req.query.concepterId || null;
        const rows = await MachineModel.findMany({ catalog, includeAll, unassigned, concepterId });
        res.set('Cache-Control', 'no-store');
        return res.json(rows.map(serializeMachine));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function create(req, res) {
    try {
        const name = String(req.body.name || '').trim();
        if (!name) return res.status(400).json({ error: 'Nom machine obligatoire' });
        const row = await MachineModel.create(req.body);
        return res.status(201).json(serializeMachine(row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getById(req, res) {
    try {
        const row = await MachineModel.findById(req.params.machineId);
        if (!row) return res.status(404).json({ error: 'Machine introuvable' });
        return res.json(serializeMachine(row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function stop(req, res) {
    try {
        const { machineId } = req.params;
        const { reason, stoppedBy } = req.body;

        console.log(`🛑 ARRÊT D'URGENCE machine ${machineId} par ${stoppedBy || 'inconnu'}. Raison: ${reason || 'non spécifiée'}`);

        const row = await MachineModel.updateStatus(machineId, 'STOPPED');
        return res.json({
            success: true,
            message: 'Machine arrêtée avec succès',
            machine: serializeMachine(row)
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function remove(req, res) {
    try {
        const { machineId } = req.params;
        await MachineModel.remove(machineId);
        return res.json({
            success: true,
            message: 'Machine supprimée avec succès'
        });
    } catch (err) {
        console.error('Erreur lors de la suppression de la machine:', err);
        return res.status(500).json({ error: err.message });
    }
}

async function update(req, res) {
    try {
        const { machineId } = req.params;
        const row = await MachineModel.update(machineId, req.body);
        return res.json(serializeMachine(row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function start(req, res) {
    try {
        const { machineId } = req.params;
        console.log(`🚀 DÉMARRAGE machine ${machineId}`);
        const row = await MachineModel.updateStatus(machineId, 'RUNNING');
        return res.json({
            success: true,
            message: 'Machine démarrée avec succès',
            machine: serializeMachine(row)
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = { list, create, getById, update, stop, start, remove };
