const Telemetry = require('../models/Telemetry');
const Machine = require('../models/Machine');
const alertService = require('../services/alertService');

exports.addTelemetry = async (req, res) => {
    try {
        const telemetry = new Telemetry(req.body);
        await telemetry.save();

        // Check thresholds and create alerts if needed
        const machine = await Machine.findById(req.body.machineId);
        if (machine) {
            const alerts = await alertService.checkThresholds(telemetry, machine);
            return res.status(201).json({
                telemetry,
                alerts: alerts.length > 0 ? alerts : undefined
            });
        }

        res.status(201).json({ telemetry });
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.getLatestTelemetry = async (req, res) => {
    try {
        const { machineId } = req.params;
        const telemetry = await Telemetry.findOne({ machineId }).sort({ createdAt: -1 });
        if (!telemetry) {
            return res.status(404).json({ message: 'Pas de données' });
        }
        res.json(telemetry);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.getHistory = async (req, res) => {
    try {
        const { machineId } = req.params;
        const history = await Telemetry.find({ machineId })
            .sort({ createdAt: -1 })
            .limit(20); // Last 20 points
        res.json(history);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
