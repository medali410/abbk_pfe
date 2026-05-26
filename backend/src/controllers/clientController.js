const ClientModel = require('../models/clientModel');
const MachineModel = require('../models/machineModel');
const { serializeMachine } = require('../views/machineView');
const { createUserWithProfile } = require('../lib/auth');
const { mergeUserProfile } = require('../views/userView');

const { nextBusinessId } = require('../lib/ids');

async function list(req, res) {
    try {
        const rows = await ClientModel.findAllWithUsers();
        res.set('Cache-Control', 'no-store');
        return res.json(rows.map((c) => mergeUserProfile(c.user, c)));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function create(req, res) {
    try {
        const email = String(req.body.email || '').trim().toLowerCase();
        const nom = String(req.body.name || req.body.nom || '').trim();
        const password = String(req.body.password || 'Dali2026!');
        if (!email.includes('@') || !nom) {
            return res.status(400).json({ error: 'Email et nom obligatoires' });
        }
        const { user, profile } = await createUserWithProfile(
            'client',
            {
                email,
                nom,
                password,
                adresse: String(req.body.adresse || req.body.address || '').trim(),
            },
            {
                clientId: nextBusinessId('CLI'),
                motorType: String(req.body.motorType || 'Général'),
                location: String(req.body.location || '').trim(),
            },
        );
        return res.status(201).json(mergeUserProfile(user, profile));
    } catch (err) {
        return res.status(err.status || 500).json({ error: err.message });
    }
}

async function getById(req, res) {
    try {
        const row = await ClientModel.findByParam(req.params.id);
        if (!row) return res.status(404).json({ error: 'Client introuvable' });
        return res.json(mergeUserProfile(row.user, row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getMachines(req, res) {
    try {
        const { id } = req.params;
        const machines = await MachineModel.findManyByCompany(id);
        return res.json(machines.map(serializeMachine));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function update(req, res) {
    try {
        const { id } = req.params;
        const { name, nom, email, password, adresse, address, location } = req.body;
        const updated = await ClientModel.updateClient(id, {
            nom: nom || name,
            adresse: adresse || address,
            email,
            password,
            location,
        });
        if (!updated) return res.status(404).json({ error: 'Client introuvable' });
        return res.json(mergeUserProfile(updated.user, updated));
    } catch (err) {
        return res.status(err.status || 500).json({ error: err.message });
    }
}

async function remove(req, res) {
    try {
        const deleted = await ClientModel.deleteClient(req.params.id);
        if (!deleted) return res.status(404).json({ error: 'Client introuvable' });
        return res.json({ ok: true });
    } catch (err) {
        return res.status(err.status || 500).json({ error: err.message });
    }
}

module.exports = { list, create, getById, getMachines, update, remove };
