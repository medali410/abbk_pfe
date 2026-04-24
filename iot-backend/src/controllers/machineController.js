const Machine = require('../models/Machine');
const Telemetry = require('../models/Telemetry');

exports.getAllMachines = async (req, res) => {
    try {
        const machines = await Machine.find().sort({ createdAt: -1 });

        // Attach latest telemetry to each machine
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
        res.status(201).json(machine);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.updateMachine = async (req, res) => {
    try {
        const machine = await Machine.findByIdAndUpdate(req.params.id, req.body, { new: true });
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

// Called by n8n to update machine status after AI analysis
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
        res.json({ success: true, machineId: machine._id, name: machine.name, status });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

