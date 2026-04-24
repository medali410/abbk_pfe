const MaintenanceOrder = require('../models/MaintenanceOrder');
const Machine = require('../models/Machine');
const DiagnosticIntervention = require('../models/DiagnosticIntervention');

exports.createOrder = async (req, res) => {
    try {
        const order = new MaintenanceOrder(req.body);
        await order.save();

        // Optionally update machine status to MAINTENANCE
        await Machine.findByIdAndUpdate(req.body.machineId, { status: 'MAINTENANCE' });

        res.status(201).json(order);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.getOrders = async (req, res) => {
    try {
        const query = {};
        if (req.query.technicianId) query.technicianId = req.query.technicianId;
        if (req.query.companyId) query.companyId = req.query.companyId;
        if (req.query.status) query.status = req.query.status;

        const orders = await MaintenanceOrder.find(query)
            .populate('machineId')
            .populate('technicianId', 'username email location')
            .sort({ createdAt: -1 });
        res.json(orders);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.updateOrder = async (req, res) => {
    try {
        const { id } = req.params;
        const order = await MaintenanceOrder.findByIdAndUpdate(id, req.body, { new: true });

        // If status is being updated to COMPLETED, mark machine as RUNNING
        if (req.body.status === 'COMPLETED' && order) {
            await Machine.findByIdAndUpdate(order.machineId, { status: 'RUNNING' });
        }

        res.json(order);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.updateOrderStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { status } = req.body;

        const order = await MaintenanceOrder.findByIdAndUpdate(id, { status }, { new: true });

        // If order is completed, maybe mark machine as RUNNING again
        if (status === 'COMPLETED' && order) {
            await Machine.findByIdAndUpdate(order.machineId, { status: 'RUNNING' });
        }

        res.json(order);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.deleteOrder = async (req, res) => {
    try {
        await MaintenanceOrder.findByIdAndDelete(req.params.id);
        res.json({ message: 'Ordre supprimé' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.requestControl = async (req, res) => {
    try {
        const { machineId, companyId, technicianId, message, status } = req.body;
        console.log('[DEBUG] requestControl body:', req.body);

        const order = new MaintenanceOrder({
            machineId,
            companyId,
            technicianId: technicianId || undefined,
            description: message || `Demande de contrôle automatique (Machine ${status})`,
            priority: 'HIGH',
            status: technicianId ? 'IN_PROGRESS' : 'PENDING'
        });

        await order.save();

        // Update machine status to MAINTENANCE
        await Machine.findByIdAndUpdate(machineId, { status: 'MAINTENANCE' });

        console.log(`[NOTIFICATION] Demande de contrôle envoyée pour la machine ${machineId}${technicianId ? ` (Assignée au tech: ${technicianId})` : ''}`);

        res.status(201).json(order);
    } catch (error) {
        console.error('[CRITICAL] Maintenance Request Error:', error);
        res.status(400).json({ message: error.message });
    }
};

// ---------------------------------------------------------
// DIAGNOSTIC INTERVENTIONS (GUIDED MAINTENANCE)
// ---------------------------------------------------------

exports.getDiagnosticInterventions = async (req, res) => {
    try {
        const query = {};
        if (req.query.machineId) query.machineId = req.query.machineId;
        if (req.query.companyId) query.companyId = req.query.companyId;
        if (req.query.status) query.status = req.query.status;

        const interventions = await DiagnosticIntervention.find(query).sort({ createdAt: -1 });
        res.json(interventions);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.createDiagnosticIntervention = async (req, res) => {
    try {
        const { machineId, scenarioType, summary } = req.body;
        
        // Define labels based on scenarioType
        const scenarioLabels = {
            'ELECTRICAL': 'Panne électrique',
            'THERMAL': 'Surchauffe thermique',
            'VIBRATION': 'Anomalie vibratoire',
            'PRESSURE': 'Anomalie pression/process',
            'SENSOR_COMM': 'Capteur / communication'
        };

        const intervention = new DiagnosticIntervention({
            ...req.body,
            scenarioLabel: scenarioLabels[scenarioType] || scenarioType,
            status: 'OPEN'
        });

        await intervention.save();

        // Update machine status to MAINTENANCE
        await Machine.findByIdAndUpdate(machineId, { status: 'MAINTENANCE' });

        res.status(201).json(intervention);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.addDiagnosticMessage = async (req, res) => {
    try {
        const { id } = req.params;
        const { content, authorId, authorRole, authorName } = req.body;

        const intervention = await DiagnosticIntervention.findById(id);
        if (!intervention) return res.status(404).json({ message: 'Intervention not found' });

        intervention.messages.push({
            content,
            authorId,
            authorRole,
            authorName,
            createdAt: new Date()
        });

        await intervention.save();
        res.json(intervention);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.addDiagnosticStep = async (req, res) => {
    try {
        const { id } = req.params;
        const { title, details } = req.body;

        const intervention = await DiagnosticIntervention.findById(id);
        if (!intervention) return res.status(404).json({ message: 'Intervention not found' });

        const order = intervention.steps.length + 1;
        intervention.steps.push({
            order,
            title,
            details,
            status: 'PENDING'
        });

        await intervention.save();
        res.json(intervention);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.markDiagnosticStepOk = async (req, res) => {
    try {
        const { id, stepId } = req.params;
        const { note } = req.body;

        const intervention = await DiagnosticIntervention.findById(id);
        if (!intervention) return res.status(404).json({ message: 'Intervention not found' });

        const step = intervention.steps.id(stepId);
        if (!step) return res.status(404).json({ message: 'Step not found' });

        step.status = 'DONE';
        step.doneAt = new Date();
        step.note = note || '';

        await intervention.save();
        res.json(intervention);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.nextDiagnosticStep = async (req, res) => {
    try {
        const { id } = req.params;
        const intervention = await DiagnosticIntervention.findById(id);
        if (!intervention) return res.status(404).json({ message: 'Intervention not found' });

        intervention.currentStepIndex += 1;
        await intervention.save();
        res.json(intervention);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.setDiagnosticDecision = async (req, res) => {
    try {
        const { id } = req.params;
        const { finalDecision, finalNote } = req.body;

        const intervention = await DiagnosticIntervention.findByIdAndUpdate(
            id, 
            { finalDecision, finalNote }, 
            { new: true }
        );

        res.json(intervention);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.updateDiagnosticStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { status } = req.body;

        const intervention = await DiagnosticIntervention.findByIdAndUpdate(
            id, 
            { status, finishedAt: status === 'DONE' ? new Date() : null }, 
            { new: true }
        );

        // If DONE, maybe machine is RUNNING again
        if (status === 'DONE' && intervention) {
            await Machine.findByIdAndUpdate(intervention.machineId, { status: 'RUNNING' });
        }

        res.json(intervention);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.deleteDiagnosticIntervention = async (req, res) => {
    try {
        const { id } = req.params;
        await DiagnosticIntervention.findByIdAndDelete(id);
        res.json({ message: 'Intervention deleted successfully' });
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.reassignTechnician = async (req, res) => {
    try {
        const { id } = req.params;
        const { technicianId, technicianName } = req.body;
        const intervention = await DiagnosticIntervention.findByIdAndUpdate(
            id,
            { technicianId, technicianName },
            { new: true }
        );
        res.json(intervention);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};
