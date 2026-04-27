const Controle = require('../models/Controle');

exports.getAllControles = async (req, res) => {
    try {
        const controles = await Controle.find().sort({ createdAt: -1 });
        res.json(controles);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.getControlesByTechnician = async (req, res) => {
    try {
        const controles = await Controle.find({ technicienId: req.params.id }).sort({ dateControle: 1 });
        res.json(controles);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.getControlesByMachine = async (req, res) => {
    try {
        const controles = await Controle.find({ machineId: req.params.id }).sort({ dateControle: -1 });
        res.json(controles);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.updateControleStatus = async (req, res) => {
    try {
        const { statut, notes } = req.body;
        const updateData = { statut };
        if (notes !== undefined) updateData.notes = notes;

        const controle = await Controle.findByIdAndUpdate(
            req.params.id,
            { $set: updateData },
            { new: true }
        );

        if (!controle) return res.status(404).json({ message: 'Contrôle non trouvé' });
        res.json(controle);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.getControlesByMonth = async (req, res) => {
    try {
        const { month } = req.params; // Format YYYY-MM
        const start = new Date(`${month}-01T00:00:00.000Z`);
        const end = new Date(start);
        end.setMonth(start.getMonth() + 1);

        const controles = await Controle.find({
            dateControle: {
                $gte: start,
                $lt: end
            }
        }).sort({ dateControle: 1 });

        res.json(controles);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
