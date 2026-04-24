const Alert = require('../models/Alert');

/**
 * Get all alerts with optional filters
 */
exports.getAllAlerts = async (req, res) => {
    try {
        const { resolved, severity, machineId } = req.query;

        const filter = {};
        if (resolved !== undefined) {
            filter.resolved = resolved === 'true';
        }
        if (severity) {
            filter.severity = severity;
        }
        if (machineId) {
            filter.machineId = machineId;
        }

        const alerts = await Alert.find(filter)
            .sort({ createdAt: -1 })
            .populate('machineId', 'name location status');

        res.json(alerts);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

/**
 * Get alerts for a specific machine
 */
exports.getAlertsByMachine = async (req, res) => {
    try {
        const { machineId } = req.params;
        const { resolved } = req.query;

        const filter = { machineId };
        if (resolved !== undefined) {
            filter.resolved = resolved === 'true';
        }

        const alerts = await Alert.find(filter)
            .sort({ createdAt: -1 })
            .limit(50);

        res.json(alerts);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

/**
 * Resolve an alert
 */
exports.resolveAlert = async (req, res) => {
    try {
        const { id } = req.params;

        const alert = await Alert.findById(id);
        if (!alert) {
            return res.status(404).json({ message: 'Alerte non trouvée' });
        }

        alert.resolved = true;
        alert.resolvedAt = new Date();
        await alert.save();

        res.json(alert);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

/**
 * Delete an alert (admin only)
 */
exports.deleteAlert = async (req, res) => {
    try {
        const { id } = req.params;

        const alert = await Alert.findByIdAndDelete(id);
        if (!alert) {
            return res.status(404).json({ message: 'Alerte non trouvée' });
        }

        res.json({ message: 'Alerte supprimée' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

/**
 * Get alert statistics
 */
exports.getAlertStats = async (req, res) => {
    try {
        const totalAlerts = await Alert.countDocuments();
        const unresolvedAlerts = await Alert.countDocuments({ resolved: false });
        const highSeverityAlerts = await Alert.countDocuments({ resolved: false, severity: 'HIGH' });
        const mediumSeverityAlerts = await Alert.countDocuments({ resolved: false, severity: 'MEDIUM' });

        res.json({
            total: totalAlerts,
            unresolved: unresolvedAlerts,
            high: highSeverityAlerts,
            medium: mediumSeverityAlerts
        });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

/**
 * Create a new alert
 */
exports.createAlert = async (req, res) => {
    try {
        const alert = new Alert(req.body);
        await alert.save();
        res.status(201).json(alert);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};
