const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const Conception = require('../models/Conception');
const Company = require('../models/Company');
const Client = require('../models/Client');

const CONCEPTION_DOC_TYPES = new Set([
    'Plan mécanique',
    'Schéma électrique',
    'Rapport technique',
    'Manuel maintenance',
]);

/**
 * Même logique métier que server.js (POST/GET /api/conceptions).
 * Utile si src/routes/api.js est monté derrière auth ; l’entrée principale reste server.js.
 */
exports.createConception = async (req, res) => {
    try {
        const name = String(req.body.name || '').trim();
        const version = String(req.body.version || 'v1.0').trim();
        const documentType = String(req.body.documentType || '').trim();
        const clientIdParam = req.body.clientId != null ? String(req.body.clientId).trim() : '';
        const securityEmail = req.body.securityEmail ? String(req.body.securityEmail).trim().toLowerCase() : '';
        const passwordPlain = req.body.password != null ? String(req.body.password) : '';
        const fileName = req.body.fileName ? String(req.body.fileName).trim() : '';
        const fileSize = req.body.fileSize ? String(req.body.fileSize).trim() : '';

        if (!name) {
            return res.status(400).json({ error: 'Nom du document obligatoire' });
        }
        if (!CONCEPTION_DOC_TYPES.has(documentType)) {
            return res.status(400).json({ error: 'Type de document invalide' });
        }
        if (!clientIdParam) {
            return res.status(400).json({ error: 'Vous devez sélectionner un client (pilote des machines)' });
        }

        const client =
            (await Client.findOne({ clientId: clientIdParam })) ||
            (mongoose.Types.ObjectId.isValid(clientIdParam) ? await Client.findById(clientIdParam) : null);
        if (!client) {
            return res.status(400).json({ error: 'Client introuvable' });
        }

        let companyRef = null;
        if (mongoose.Types.ObjectId.isValid(String(client._id))) {
            const co = await Company.findById(client._id);
            if (co) companyRef = co._id;
        }

        const assignedClientId = client.clientId ? String(client.clientId) : String(client._id);

        let secPass;
        if (passwordPlain && passwordPlain.length > 0) {
            secPass = await bcrypt.hash(passwordPlain, 10);
        }

        const doc = new Conception({
            name,
            version: version || 'v1.0',
            documentType,
            company: companyRef || undefined,
            clientId: assignedClientId,
            securityEmail: securityEmail || undefined,
            password: secPass,
            status: 'BROUILLON',
            fileName: fileName || undefined,
            fileSize: fileSize || undefined,
        });
        await doc.save();

        const out = {
            id: String(doc._id),
            name: doc.name,
            version: doc.version,
            documentType: doc.documentType,
            clientId: doc.clientId,
            clientName: client.name,
            status: doc.status,
            securityEmail: doc.securityEmail || null,
            fileName: doc.fileName || null,
            fileSize: doc.fileSize || null,
        };
        return res.status(201).json(out);
    } catch (error) {
        console.error('Error in createConception:', error);
        return res.status(500).json({ error: error.message || 'Server error' });
    }
};

exports.getAllConceptions = async (req, res) => {
    try {
        const docs = await Conception.find().sort({ updatedAt: -1 }).lean();
        for (const d of docs) {
            d.id = String(d._id);
            delete d._id;
            delete d.password;
            if (d.company) {
                const co = await Company.findById(d.company).select('name').lean();
                d.company = co ? { _id: d.company, name: co.name } : null;
            }
            if (d.clientId) {
                const cl =
                    (await Client.findOne({ clientId: d.clientId })) ||
                    (mongoose.Types.ObjectId.isValid(d.clientId) ? await Client.findById(d.clientId) : null);
                if (cl) d.clientName = cl.name;
            }
        }
        res.set('Cache-Control', 'no-store');
        return res.status(200).json(docs);
    } catch (error) {
        console.error('Error in getAllConceptions:', error);
        return res.status(500).json({ error: error.message || 'Server error' });
    }
};
