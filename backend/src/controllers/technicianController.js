// src/controllers/technicianController.js
const TechnicianModel = require('../models/technicianModel');
const { serializeTechnician, serializeTechnicianDashboard } = require('../views/technicianView');
const { createUserWithProfile, hashPassword, getAuthUserId } = require('../lib/auth');
const { prisma } = require('../lib/prisma');

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Charge machines + télémétries pour un profil Technician. */
async function loadMachineData(profile) {
    let machineIds = [];
    try { machineIds = JSON.parse(profile.machineIds || '[]'); } catch (_) {}

    const machines = machineIds.length
        ? await prisma.machine.findMany({
              where: { id: { in: machineIds } },
              select: { id: true, name: true, type: true, status: true, location: true, motorType: true },
          })
        : [];

    const telemetryMap = {};
    for (const m of machines) {
        const t = await prisma.telemetry.findFirst({
            where: { machineId: m.id },
            orderBy: { timestamp: 'desc' },
        });
        if (t) {
            telemetryMap[m.id] = {
                ...t,
                temperature: t.temp,
                pressure: t.voltage,
                voltage: t.voltage,
                magnetic: t.magnet
            };
        }
    }
    return { machines, telemetryMap };
}

// ─── Admin / Fleet Manager ────────────────────────────────────────────────────

/** GET /api/technicians */
async function listTechnicians(req, res) {
    try {
        const { status, companyId, specialization, machineId } = req.query;
        let rows = await TechnicianModel.listTechnicians({ status, companyId, specialization });
        
        if (machineId) {
            rows = rows.filter(p => {
                let mIds = [];
                try { mIds = JSON.parse(p.machineIds || '[]'); } catch(e) {}
                return mIds.includes(String(machineId));
            });
        }
        
        res.set('Cache-Control', 'no-store');
        return res.json(rows.map(p => serializeTechnician(p.user, p)));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** GET /api/technicians/:id */
async function getTechnician(req, res) {
    try {
        const row = await TechnicianModel.getTechnicianByIdOrCode(req.params.id);
        if (!row) return res.status(404).json({ error: 'Technicien introuvable' });
        return res.json(serializeTechnician(row.user, row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** POST /api/technicians */
async function createTechnician(req, res) {
    let createdUserId = null;
    try {
        const {
            email, password, name,
            firstName = '', lastName = '',
            address = '', companyId = '',
            specialization = 'Vibration',
            status = 'Disponible',
            machineIds = [],
        } = req.body;

        if (!email || !password)
            return res.status(400).json({ error: 'email et password sont obligatoires' });

        const { user, profile } = await createUserWithProfile(
            'technician',
            { email, nom: name || `${firstName} ${lastName}`.trim(), password, adresse: address },
            {
                firstName, lastName, companyId, specialization, status,
                machineIds: JSON.stringify(Array.isArray(machineIds) ? machineIds : []),
            },
        );
        createdUserId = user.id;
        return res.status(201).json(serializeTechnician(user, profile));
    } catch (err) {
        if (createdUserId) {
            try { await prisma.user.delete({ where: { id: createdUserId } }); } catch (_) {}
        }
        return res.status(err.status || 500).json({ error: err.message });
    }
}

/** PUT /api/technicians/:id */
async function updateTechnician(req, res) {
    try {
        const existing = await TechnicianModel.getTechnicianByIdOrCode(req.params.id);
        if (!existing) return res.status(404).json({ error: 'Technicien introuvable' });

        const { email, password, name, firstName, lastName, address, companyId, specialization, status, machineIds } = req.body;

        const userData = {};
        if (email)    userData.email    = email;
        if (name)     userData.nom      = name;
        if (address)  userData.adresse  = address;
        if (password) userData.password = await hashPassword(password);

        const updatedUser = Object.keys(userData).length
            ? await prisma.user.update({ where: { id: existing.userId }, data: userData })
            : existing.user;

        const profileData = {};
        if (firstName      !== undefined) profileData.firstName      = firstName;
        if (lastName       !== undefined) profileData.lastName       = lastName;
        if (companyId      !== undefined) profileData.companyId      = companyId;
        if (specialization !== undefined) profileData.specialization = specialization;
        if (status         !== undefined) profileData.status         = status;
        if (machineIds     !== undefined) profileData.machineIds     = JSON.stringify(Array.isArray(machineIds) ? machineIds : []);

        const updatedProfile = Object.keys(profileData).length
            ? await TechnicianModel.updateTechnicianProfile(existing.id, profileData)
            : existing;

        return res.json(serializeTechnician(updatedUser, updatedProfile));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** DELETE /api/technicians/:id */
async function deleteTechnician(req, res) {
    try {
        const existing = await TechnicianModel.getTechnicianByIdOrCode(req.params.id);
        if (!existing) return res.status(404).json({ error: 'Technicien introuvable' });
        await TechnicianModel.deleteTechnician(existing.userId);
        return res.json({ success: true, deleted: existing.technicianId });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** PATCH /api/technicians/:id/machines */
async function assignMachines(req, res) {
    try {
        const existing = await TechnicianModel.getTechnicianByIdOrCode(req.params.id);
        if (!existing) return res.status(404).json({ error: 'Technicien introuvable' });

        const { machineIds = [] } = req.body;
        if (!Array.isArray(machineIds))
            return res.status(400).json({ error: 'machineIds doit être un tableau' });

        const updated = await TechnicianModel.setMachineIds(existing.id, machineIds);
        return res.json(serializeTechnician(existing.user, updated));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── Self (technicien connecté) ───────────────────────────────────────────────

/** GET /api/technicians/me */
async function getMyProfile(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const profile = await TechnicianModel.getTechnicianByUserId(userId);
        if (!profile) return res.status(404).json({ error: 'Profil technicien introuvable' });

        const { machines, telemetryMap } = await loadMachineData(profile);

        res.set('Cache-Control', 'no-store');
        return res.json(serializeTechnicianDashboard(profile.user, profile, machines, telemetryMap));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** PATCH /api/technicians/me */
async function updateMyProfile(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const profile = await TechnicianModel.getTechnicianByUserId(userId);
        if (!profile) return res.status(404).json({ error: 'Profil technicien introuvable' });

        const { nom, adresse, firstName, lastName, password } = req.body;

        const userData = {};
        if (nom)      userData.nom     = nom;
        if (adresse)  userData.adresse = adresse;
        if (password) userData.password = await hashPassword(password);

        const updatedUser = Object.keys(userData).length
            ? await prisma.user.update({ where: { id: userId }, data: userData })
            : profile.user;

        const profileData = {};
        if (firstName !== undefined) profileData.firstName = firstName;
        if (lastName  !== undefined) profileData.lastName  = lastName;

        const updatedProfile = Object.keys(profileData).length
            ? await TechnicianModel.updateTechnicianProfile(profile.id, profileData)
            : profile;

        return res.json(serializeTechnician(updatedUser, updatedProfile));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** GET /api/technicians/me/telemetry */
async function getMyMachinesTelemetry(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const profile = await TechnicianModel.getTechnicianByUserId(userId);
        if (!profile) return res.status(404).json({ error: 'Profil technicien introuvable' });

        let machineIds = [];
        try { machineIds = JSON.parse(profile.machineIds || '[]'); } catch (_) {}

        const results = await Promise.all(
            machineIds.map(async (mid) => {
                const machine   = await prisma.machine.findUnique({ where: { id: mid }, select: { id: true, name: true, status: true, type: true } });
                const telemetry = await prisma.telemetry.findFirst({ where: { machineId: mid }, orderBy: { timestamp: 'desc' } });
                const mappedTelemetry = telemetry ? {
                    ...telemetry,
                    temperature: telemetry.temp,
                    pressure: telemetry.voltage,
                    voltage: telemetry.voltage,
                    magnetic: telemetry.magnet
                } : null;
                return { machine: machine || { id: mid, name: 'Inconnue' }, telemetry: mappedTelemetry };
            }),
        );
        return res.json(results);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = {
    listTechnicians, getTechnician, createTechnician, updateTechnician,
    deleteTechnician, assignMachines, getMyProfile, updateMyProfile, getMyMachinesTelemetry,
};
