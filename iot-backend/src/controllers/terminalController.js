/**
 * Terminal Controller
 * Handles data for the high-tech technician terminal (DZLI)
 */

exports.getTerminalData = async (req, res) => {
    try {
        // In a real app, you would fetch real sensor data from DB or MQTT
        // For the demo, we provide high-precision simulated data
        const terminalData = {
            sessionId: "9822-XP",
            nodeId: "NODE_01",
            sector: "G7",
            metrics: {
                thermal: { value: 38.2, status: "STABLE", range: [34.0, 41.2] },
                pressure: { value: 101.4, status: "NOMINAL", ref: 101.3 },
                power: { value: 8.2, load: "72%", alert: "PEAK_ALERT" },
                ultrasonic: { value: 42, band: "HIGH" },
                presence: { value: 1, authId: "ALPHA-9" },
                magnetic: { value: 14.8, axis: "Z-REL", status: "FLUX_STABLE" }
            },
            systemHealth: {
                processorLoad: 42,
                storageCapacity: 89,
                latency: 12,
                uptime: "104:12"
            },
            logs: [
                { time: "14:21:05", type: "SYSTEM", content: "BIO_METRIC AUTHENTICATION SUCCESSFUL / ID: ALPHA-9" },
                { time: "14:20:58", type: "WARNING", content: "GRID NODE 07 POWER SPIKE DETECTED / COMPENSATING..." },
                { time: "14:10:22", type: "INTEL", content: "THERMAL SENSOR 4 CALIBRATION COMPLETE" },
                { time: "14:15:10", type: "SYNC", content: "DATA UPLOAD TO CENTRAL ARCHIVES SECURED" }
            ]
        };

        res.status(200).json(terminalData);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};
