const MachineModel = require('../models/machineModel');
const { serializeMachine } = require('../views/machineView');
const { validateCreateMachine, validateUpdateMachine } = require('../lib/validators');

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
        const createErrors = validateCreateMachine(req.body);
        if (createErrors.length > 0) {
            return res.status(400).json({ error: createErrors.join(' | '), errors: createErrors });
        }
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
        const updateErrors = validateUpdateMachine(req.body);
        if (updateErrors.length > 0) {
            return res.status(400).json({ error: updateErrors.join(' | '), errors: updateErrors });
        }
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

const { prisma } = require('../lib/prisma');
const mqtt = require('../lib/mqtt');

async function saveConfigAndPublish(req, res) {
    try {
        const { machineId } = req.params;
        const { ssid, password, newMachineId } = req.body;

        if (!ssid || !password) {
            return res.status(400).json({ error: 'SSID et mot de passe WiFi obligatoires' });
        }

        // 1. Publication MQTT (sur l'ancien topic pour que l'ESP32 reçoive la config)
        const topic = `machines/${machineId}/config`;
        const payload = {
            ssid,
            password,
            machineId: newMachineId || machineId
        };
        mqtt.publish(topic, payload);

        // 2. Sauvegarde en DB
        let row;
        if (newMachineId && newMachineId !== machineId) {
            // Mettre à jour l'ID (clé primaire) et les infos WiFi dans la DB
            row = await prisma.machine.update({
                where: { id: String(machineId) },
                data: {
                    id: String(newMachineId),
                    wifiSsid: ssid,
                    wifiPassword: password
                }
            });
            console.log(`🆔 ID de la machine mis à jour en DB de ${machineId} à ${newMachineId}`);
        } else {
            row = await MachineModel.update(machineId, {
                wifiSsid: ssid,
                wifiPassword: password
            });
        }

        return res.json({
            success: true,
            message: 'WiFi et ID configurés et publiés sur MQTT avec succès',
            machine: serializeMachine(row)
        });
    } catch (err) {
        console.error('Erreur saveConfigAndPublish:', err);
        return res.status(500).json({ error: err.message });
    }
}

module.exports = { list, create, getById, update, stop, start, remove, saveConfigAndPublish };
