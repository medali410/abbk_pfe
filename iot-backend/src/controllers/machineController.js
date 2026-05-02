const Machine = require('../models/Machine');
const Telemetry = require('../models/Telemetry');
const Controle = require('../models/Controle');
const { ensureMotorSensorRoutineSeuilById } = require('../utils/motorSensorRoutineSeuil');

// ── Socket.IO instance (injectée depuis server.js) ──────────────────────────
let _io = null;
exports.setIo = (io) => { _io = io; };
// ────────────────────────────────────────────────────────────────────────────

exports.getAllMachines = async (req, res) => {
    try {
        const machines = await Machine.find().sort({ createdAt: -1 });

        const machinesWithTelemetry = await Promise.all(machines.map(async (machine) => {
            const latestTelemetry = await Telemetry.findOne({ machineId: machine._id }).sort({ createdAt: -1 });
            const machineObj = machine.toObject();
            machineObj.telemetry = latestTelemetry;
            return machineObj;
        }));

        res.json(machinesWithTelemetry);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.getMachineById = async (req, res) => {
    try {
        const machine = await Machine.findById(req.params.id);
        if (!machine) return res.status(404).json({ message: 'Machine non trouvée' });

        const latestTelemetry = await Telemetry.findOne({ machineId: machine._id }).sort({ createdAt: -1 });
        const machineObj = machine.toObject();
        machineObj.telemetry = latestTelemetry;

        res.json(machineObj);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.createMachine = async (req, res) => {
    try {
        const machine = new Machine(req.body);
        await machine.save();
        try {
            await ensureMotorSensorRoutineSeuilById(Machine, machine._id);
        } catch (e) {
            console.warn('ensureMotorSensorRoutineSeuilById (createMachine):', e.message);
        }
        const fresh = await Machine.findById(machine._id);
        res.status(201).json(fresh || machine);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.updateMachine = async (req, res) => {
    try {
        const body = { ...req.body };
        if (body.seuilsControle && typeof Machine.normalizeSeuilsControle === 'function') {
            body.seuilsControle = Machine.normalizeSeuilsControle(body.seuilsControle);
        }
        const machine = await Machine.findByIdAndUpdate(req.params.id, body, { new: true });
        res.json(machine);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.deleteMachine = async (req, res) => {
    try {
        await Machine.findByIdAndDelete(req.params.id);
        res.json({ message: 'Machine supprimée' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.updateMachineParameters = async (req, res) => {
    try {
        const { parameters } = req.body;
        console.log(`[DEBUG] Update parameters for machine ${req.params.id}:`, JSON.stringify(parameters, null, 2));

        if (!Array.isArray(parameters)) {
            return res.status(400).json({ message: '`parameters` doit être un tableau' });
        }

        const machine = await Machine.findByIdAndUpdate(
            req.params.id,
            { $set: { parameters } },
            { new: true, runValidators: true }
        );

        if (!machine) {
            console.log(`[DEBUG] Machine ${req.params.id} not found`);
            return res.status(404).json({ message: 'Machine non trouvée' });
        }

        console.log(`[DEBUG] Update successful for machine ${req.params.id}`);
        res.json(machine);
    } catch (error) {
        console.error(`[DEBUG] Error updating parameters for ${req.params.id}:`, error);
        res.status(400).json({ message: error.message });
    }
};

// Called by n8n / dashboard to update machine status after AI analysis
exports.updateMachineStatus = async (req, res) => {
    try {
        const { status, aiDiagnosis } = req.body;
        const validStatuses = ['RUNNING', 'DEGRADED', 'STOPPED', 'MAINTENANCE'];

        if (!validStatuses.includes(status)) {
            return res.status(400).json({ message: `Statut invalide. Valeurs: ${validStatuses.join(', ')}` });
        }

        const machine = await Machine.findByIdAndUpdate(
            req.params.id,
            {
                $set: {
                    status: status,
                    lastAIDiagnosis: aiDiagnosis || null,
                    lastAICheck: new Date()
                }
            },
            { new: true }
        );

        if (!machine) return res.status(404).json({ message: 'Machine non trouvée' });

        console.log(`[n8n] ✅ Statut machine "${machine.name}" mis à jour → ${status}`);

        // ── Socket.IO : machine_status ────────────────────────────────────────
        if (_io) {
            _io.emit('machine_status', {
                machineId:   String(machine._id),
                machineName: machine.name,
                status:      machine.status,
                ts:          new Date().toISOString(),
            });
            console.log(`🔔 Socket.IO → machine_status ${machine.name} : ${status}`);

            // ── controle_urgent : vérifier contrôles urgents planifiés ─────────
            const urgents = await Controle.find({
                machineId: String(machine._id),
                statut:    'planifié',
                priorite:  'urgente',
            }).lean();

            for (const c of urgents) {
                _io.emit('controle_urgent', {
                    controleId:   String(c._id),
                    machineId:    String(machine._id),
                    machineName:  machine.name,
                    typeControle: c.typeControle,
                    heures:       c.heuresDeClenchement,
                    priorite:     'urgente',
                    prioriteLabel: 'URGENTE 🔴',
                    motorType:    c.motorType,
                    dateControle: c.dateControle,
                });
                console.log(`🚨 Socket.IO → controle_urgent ${c.typeControle} pour ${machine.name}`);
            }
        }
        // ─────────────────────────────────────────────────────────────────────

        res.json({ success: true, machineId: machine._id, name: machine.name, status });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.getTempsMarche = async (req, res) => {
    try {
        const machine = await Machine.findById(req.params.id).select('tempsMarche name status');
        if (!machine) return res.status(404).json({ message: 'Machine non trouvée' });
        
        const totalHeures = machine.tempsMarche.totalHeures || 0;
        
        res.json({
            machineId: machine._id,
            machineName: machine.name,
            tempsMarche: {
                totalHeures: totalHeures,
                totalMinutes: Math.round(totalHeures * 60),
                derniereMiseAJour: machine.tempsMarche.derniereMiseAJour,
                enMarche: machine.tempsMarche.enMarche,
                debutSessionMarche: machine.tempsMarche.debutSessionMarche ?? null,
            },
            status: machine.status
        });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

