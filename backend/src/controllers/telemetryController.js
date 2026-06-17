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

exports.saveTelemetry = async (data) => {
    try {
        // Normalisation des champs pour correspondre au schéma Prisma
        await prisma.telemetry.create({
            data: {
                machineId: data.machineId || 'UNKNOWN',
                temp: parseFloat(data.temperature || data.temp || 0),
                voltage: parseFloat(data.voltage || data.tension || data.pressure || data.pression || 0),
                vibration: parseFloat(data.vibration || 0),
                magnet: parseFloat(data.magnetic || data.magnet || 0),
                presence: parseInt(data.presence || 0),
                rpm: parseInt(data.rpm || 0),
                torque: parseFloat(data.torque || 0),
                courant: parseFloat(data.courant || data.current || 0),
                puissance: parseFloat(data.puissance || data.power || 0),
                infrared: parseFloat(data.infrared || data.infrarouge || 0),
                timestamp: new Date()
            }
        });
    } catch (error) {
        console.error('Erreur sauvegarde Telemetry:', error);
    }
};
