const ClientModel = require('../models/clientModel');
const MachineModel = require('../models/machineModel');
const { serializeMachine } = require('../views/machineView');
const { createUserWithProfile, getAuthUserId, prisma } = require('../lib/auth');
const { mergeUserProfile } = require('../views/userView');

const { nextBusinessId } = require('../lib/ids');

async function list(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        const role = req.auth?.role;
        let rows;
        if (role === 'conception') {
            const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
            if (concepteur) {
                let allowedIds = [];
                try { allowedIds = JSON.parse(concepteur.machineIds || '[]'); } catch (e) { }
                const machines = await prisma.machine.findMany({
                    where: {
                        OR: [
                            { concepteurId: String(concepteur.id) },
                            { id: { in: allowedIds } }
                        ]
                    }
                });
                const clientIds = [...new Set(machines.map(m => m.companyId).filter(Boolean))];
                rows = await prisma.client.findMany({
                    where: { clientId: { in: clientIds } },
                    include: { user: true },
                    orderBy: { id: 'desc' },
                });
            } else {
                rows = [];
            }
        } else {
            rows = await ClientModel.findAllWithUsers();
        }
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

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userId = getAuthUserId(req.auth);
            const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
            if (concepteur) {
                let allowedIds = [];
                try { allowedIds = JSON.parse(concepteur.machineIds || '[]'); } catch (e) { }
                const machines = await prisma.machine.findMany({
                    where: {
                        OR: [
                            { concepteurId: String(concepteur.id) },
                            { id: { in: allowedIds } }
                        ]
                    }
                });
                const companyIds = [...new Set(machines.map(m => m.companyId).filter(Boolean))];
                if (!companyIds.includes(String(row.clientId))) {
                    return res.status(403).json({ error: 'Accès interdit. Ce client ne fait pas partie de vos relations.' });
                }
            } else {
                return res.status(403).json({ error: 'Accès interdit.' });
            }
        }
        return res.json(mergeUserProfile(row.user, row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getMachines(req, res) {
    try {
        const { id } = req.params;

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userId = getAuthUserId(req.auth);
            const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
            if (concepteur) {
                let allowedIds = [];
                try { allowedIds = JSON.parse(concepteur.machineIds || '[]'); } catch (e) { }
                const machines = await prisma.machine.findMany({
                    where: {
                        OR: [
                            { concepteurId: String(concepteur.id) },
                            { id: { in: allowedIds } }
                        ]
                    }
                });
                const companyIds = [...new Set(machines.map(m => m.companyId).filter(Boolean))];
                if (!companyIds.includes(String(id))) {
                    return res.status(403).json({ error: 'Accès interdit. Les machines de ce client ne vous concernent pas.' });
                }
            } else {
                return res.status(403).json({ error: 'Accès interdit.' });
            }
        }

        const instances = await prisma.machineInstance.findMany({
            where: { clientId: String(id) },
            include: { model: true },
            orderBy: { id: 'asc' },
        });

        return res.json(instances.map(inst => ({
            id: inst.id,
            machineId: inst.id,
            name: inst.model?.name || 'Machine',
            modelId: inst.modelId,
            ipAddress: inst.ipAddress,
            clientId: inst.clientId,
            status: inst.status,
            aiType: inst.model?.aiType || 'M',
            type: inst.model?.type || '',
            motorType: inst.model?.motorType || '',
            imageUrl: inst.model?.imageUrl || '',
            wifiSsid: inst.wifiSsid,
            purchasedAt: inst.purchasedAt,
        })));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getTechnicians(req, res) {
    try {
        const { id } = req.params;

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userId = getAuthUserId(req.auth);
            const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
            if (concepteur) {
                let allowedIds = [];
                try { allowedIds = JSON.parse(concepteur.machineIds || '[]'); } catch (e) { }
                const machines = await prisma.machine.findMany({
                    where: {
                        OR: [
                            { concepteurId: String(concepteur.id) },
                            { id: { in: allowedIds } }
                        ]
                    }
                });
                const companyIds = [...new Set(machines.map(m => m.companyId).filter(Boolean))];
                if (!companyIds.includes(String(id))) {
                    return res.status(403).json({ error: 'Accès interdit. Les techniciens de ce client ne vous concernent pas.' });
                }
            } else {
                return res.status(403).json({ error: 'Accès interdit.' });
            }
        }

        const machines = await MachineModel.findManyByCompany(id);
        const machineIdsStr = machines.map(m => String(m.id));

        const allTechs = await prisma.technician.findMany({ include: { user: true } });
        const techs = allTechs.filter(t => {
            if (t.companyId === id) return true;
            let mIds = [];
            try { mIds = JSON.parse(t.machineIds || '[]'); } catch (e) { }
            return mIds.some(mId => machineIdsStr.includes(String(mId)));
        });

        return res.json(techs.map(t => mergeUserProfile(t.user, t)));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getMaintenanceAgents(req, res) {
    try {
        const { id } = req.params;

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userId = getAuthUserId(req.auth);
            const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
            if (concepteur) {
                let allowedIds = [];
                try { allowedIds = JSON.parse(concepteur.machineIds || '[]'); } catch (e) { }
                const machines = await prisma.machine.findMany({
                    where: {
                        OR: [
                            { concepteurId: String(concepteur.id) },
                            { id: { in: allowedIds } }
                        ]
                    }
                });
                const companyIds = [...new Set(machines.map(m => m.companyId).filter(Boolean))];
                if (!companyIds.includes(String(id))) {
                    return res.status(403).json({ error: 'Accès interdit. Les agents de ce client ne vous concernent pas.' });
                }
            } else {
                return res.status(403).json({ error: 'Accès interdit.' });
            }
        }

        const machines = await MachineModel.findManyByCompany(id);
        const machineIdsStr = machines.map(m => String(m.id));

        const allAgents = await prisma.maintenanceAgent.findMany({ include: { user: true } });
        const agents = allAgents.filter(a => {
            if (a.clientId === id || a.companyId === id) return true;
            let mIds = [];
            try { mIds = JSON.parse(a.machineIds || '[]'); } catch (e) { }
            return mIds.some(mId => machineIdsStr.includes(String(mId)));
        });

        return res.json(agents.map(a => mergeUserProfile(a.user, a)));
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

module.exports = { list, create, getById, getMachines, getTechnicians, getMaintenanceAgents, update, remove };
