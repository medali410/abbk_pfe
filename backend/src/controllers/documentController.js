const DocumentModel = require('../models/documentModel');
const { serializeDocument } = require('../views/documentView');

async function list(req, res) {
    try {
        const rows = await DocumentModel.findAll();
        res.set('Cache-Control', 'no-store');
        return res.json(rows.map(serializeDocument));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function create(req, res) {
    try {
        const name = String(req.body.name || '').trim();
        const clientId = String(req.body.clientId || '').trim();
        if (!name) {
            return res.status(400).json({ error: 'Nom du document obligatoire' });
        }
        if (!clientId) {
            return res.status(400).json({ error: 'clientId obligatoire' });
        }
        const row = await DocumentModel.create(req.body);
        return res.status(201).json(serializeDocument(row));
    } catch (err) {
        return res.status(err.status || 500).json({ error: err.message });
    }
}

module.exports = { list, create };
