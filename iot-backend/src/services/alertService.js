const Alert = require('../models/Alert');

/**
 * Check telemetry values against machine-specific parameters and create alerts if needed
 * @param {Object} telemetry - Telemetry data
 * @param {Object} machine - Machine object with parameters array
 * @returns {Promise<Array>} Array of created alerts
 */
async function checkThresholds(telemetry, machine) {
    if (!machine.parameters || machine.parameters.length === 0) return [];

    const alerts = [];
    const metrics = telemetry.metrics || {};

    for (const param of machine.parameters) {
        if (!param.enabled) continue;

        // Get value from metrics map (prefer generic metrics, fallback to legacy field if param key matches)
        let value = metrics instanceof Map ? metrics.get(param.key) : metrics[param.key];

        // Final fallback for legacy fields (temperature, vibration, powerConsumption)
        if (value === undefined || value === null) {
            if (param.key === 'thermal') value = telemetry.temperature;
            else if (param.key === 'vibration') value = telemetry.vibration;
            else if (param.key === 'power') value = telemetry.powerConsumption;
        }

        if (value === undefined || value === null) continue;

        const alert = await checkParameterValue(param, value, machine);
        if (alert) alerts.push(alert);
    }

    return alerts;
}

/**
 * Check a single parameter value against its machine-specific thresholds
 */
async function checkParameterValue(param, value, machine) {
    let severity = null;
    let threshold = null;

    // Check against critical first
    if (param.criticalThreshold !== null && value >= param.criticalThreshold) {
        severity = 'HIGH';
        threshold = param.criticalThreshold;
    }
    // Then warning
    else if (param.warnThreshold !== null && value >= param.warnThreshold) {
        severity = 'MEDIUM';
        threshold = param.warnThreshold;
    }

    const type = param.key.toUpperCase();

    if (severity) {
        // Check if there's already an unresolved alert for this machine and sensor key
        const existingAlert = await Alert.findOne({
            machineId: machine._id,
            type: type,
            resolved: false
        });

        const message = generateMessage(param, machine.name, value, threshold, severity);

        if (existingAlert) {
            // Update existing alert if severity changed or value is significantly higher
            if (existingAlert.severity !== severity || Math.abs(existingAlert.value - value) > (threshold * 0.05)) {
                existingAlert.severity = severity;
                existingAlert.value = value;
                existingAlert.threshold = threshold;
                existingAlert.message = message;
                await existingAlert.save();
                return existingAlert;
            }
            return null;
        }

        // Create new alert
        const alert = new Alert({
            machineId: machine._id,
            machineName: machine.name,
            severity: severity,
            type: type,
            message: message,
            value: value,
            threshold: threshold
        });

        await alert.save();
        return alert;
    }

    // Value is normal - auto-resolve any existing alerts for this specific sensor key
    await Alert.updateMany(
        {
            machineId: machine._id,
            type: type,
            resolved: false
        },
        {
            resolved: true,
            resolvedAt: new Date()
        }
    );

    return null;
}

/**
 * Generate alert message based on dynamic parameter info
 */
function generateMessage(param, machineName, value, threshold, severity) {
    const severityLabel = severity === 'HIGH' ? 'CRITIQUE' : 'ATTENTION';
    const unit = param.unit || '';

    return `${severityLabel} - ${param.label} anormale sur ${machineName}: ${value.toFixed(1)}${unit} (seuil: ${threshold}${unit})`;
}

module.exports = {
    checkThresholds
};
