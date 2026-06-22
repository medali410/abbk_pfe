const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

exports.getLatest = async (req, res) => {
    const { machineId, limit } = req.query;
    const take = parseInt(limit) || 20;

    if (!machineId) {
        return res.status(400).json({ error: 'machineId manquant' });
    }

    try {
        const data = await prisma.telemetry.findMany({
            where: { machineId },
            orderBy: { timestamp: 'desc' },
            take: take,
        });

        // Normalize DB keys to MQTT/Frontend expected keys
        const mappedData = data.map(record => ({
            ...record,
            temperature: record.temp,
            pressure: record.voltage, // compatibilité descendante
            pression: record.voltage, // compatibilité descendante
            voltage: record.voltage,
            tension: record.voltage,
            magnetic: record.magnet,
            power: record.puissance || ((record.torque && record.rpm) ? (record.torque * record.rpm) : 0),
            puissance: record.puissance || ((record.torque && record.rpm) ? (record.torque * record.rpm) : 0),
            courant: record.courant,
            current: record.courant,
            infrared: record.infrared,
            infrarouge: record.infrared,
        }));

        res.json(mappedData);
    } catch (error) {
        console.error('Erreur Telemetry:', error);
        res.status(500).json({ error: 'Erreur lors de la récupération de la télémétrie' });
    }
};

exports.saveTelemetry = async (data, io) => {
    try {
        const vibration = parseFloat(data.vibration || 0);
        const temp = parseFloat(data.temperature || data.temp || 0);
        const magnetic = parseFloat(data.magnetic || data.magnet || 0);
        const machineId = data.machineId || 'UNKNOWN';

        // Normalisation des champs pour correspondre au schéma Prisma
        await prisma.telemetry.create({
            data: {
                machineId: machineId,
                temp: temp,
                voltage: parseFloat(data.voltage || data.tension || data.pressure || data.pression || 0),
                vibration: vibration,
                magnet: magnetic,
                presence: parseInt(data.presence || 0),
                rpm: parseInt(data.rpm || 0),
                torque: parseFloat(data.torque || 0),
                courant: parseFloat(data.courant || data.current || 0),
                puissance: parseFloat(data.puissance || data.power || 0),
                infrared: parseFloat(data.infrared || data.infrarouge || 0),
                timestamp: new Date()
            }
        });

        // 🚨 Vérification de sécurité (Arrêt d'urgence automatique)
        let dangerReason = null;
        let sensorName = null;
        let measuredValue = 0;
        let threshold = 0;

        if (vibration > 20) {
            dangerReason = "Vibration critique";
            sensorName = "vibration";
            measuredValue = vibration;
            threshold = 20;
        } else if (temp > 80) {
            dangerReason = "Température critique";
            sensorName = "temperature";
            measuredValue = temp;
            threshold = 80;
        } else if (magnetic > 100) {
            dangerReason = "Magnétisme critique";
            sensorName = "magnetic";
            measuredValue = magnetic;
            threshold = 100;
        }

        if (dangerReason && machineId !== 'UNKNOWN') {
            const machine = await prisma.machine.findUnique({ where: { id: machineId } });
            if (machine && machine.status !== 'STOPPED_DANGER') {
                console.log(`🚨 ARRÊT DANGER DÉTECTÉ sur ${machineId}: ${dangerReason} (${measuredValue})`);
                
                // 1. MQTT Publish
                const mqtt = require('../lib/mqtt');
                mqtt.publish(`machines/${machineId}/control`, JSON.stringify({ command: 'OFF', reason: 'DANGER_AUTO' }));

                // 2. Update DB
                await prisma.machine.update({
                    where: { id: machineId },
                    data: { status: 'STOPPED_DANGER' }
                });

                // 3. Security Incident Log
                await prisma.securityIncident.create({
                    data: {
                        machineId: machineId,
                        sensor: sensorName,
                        measuredValue: measuredValue,
                        threshold: threshold,
                        timestamp: new Date()
                    }
                });

                // 4. Alert Frontend
                if (io) {
                    io.emit('danger_alert', {
                        machineId: machineId,
                        reason: dangerReason,
                        sensor: sensorName,
                        value: measuredValue,
                        threshold: threshold,
                        timestamp: new Date()
                    });
                    // Aussi envoyer update de statut
                    io.emit('machine_status_update', { machineId: machineId, status: 'STOPPED_DANGER' });
                }
            }
        }
    } catch (error) {
        console.error('Erreur sauvegarde Telemetry:', error);
    }
};
