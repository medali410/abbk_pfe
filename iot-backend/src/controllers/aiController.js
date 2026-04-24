const aiService = require('../services/aiService');
const Machine = require('../models/Machine');

/**
 * Endpoint pour discuter avec l'IA au sujet d'une machine spécifique
 */
exports.chat = async (req, res) => {
    try {
        const { machineId, message } = req.body;

        if (!machineId || !message) {
            return res.status(400).json({ error: 'machineId et message sont requis.' });
        }

        // Trouver la machine pour donner du contexte à l'IA
        const machine = await Machine.findOne({ id: machineId });
        if (!machine) {
            return res.status(404).json({ error: 'Machine non trouvée.' });
        }

        const result = await aiService.chatWithAI(machineId, message, machine);
        res.status(200).json(result);

    } catch (error) {
        console.error('[AI Controller] Error:', error.message);
        res.status(500).json({ error: error.message });
    }
};
