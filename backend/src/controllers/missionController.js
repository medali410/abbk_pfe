// src/controllers/missionController.js
/**
 * Gestion des missions du technicien.
 * - Stockées en base (Mission model).
 * - Visibles dans la sidebar Flutter via GET /api/missions/me/sidebar.
 * - Notification envoyée au technicien lors de l'assignation.
 */

const MissionModel      = require('../models/missionModel');
const NotificationModel = require('../models/notificationModel');
const { serializeMission } = require('../views/missionView');
const { getAuthUserId }  = require('../lib/auth');
const { nextBusinessId } = require('../lib/ids');
const { prisma }         = require('../lib/prisma');

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function notifyTechnician(mission, type = 'MISSION_ASSIGNED') {
    try {
        const profile = await prisma.technician.findFirst({
            where: { technicianId: mission.technicianId },
        });
        if (!profile) return;

        const titles = {
            MISSION_ASSIGNED:   'Nouvelle mission assignée',
            MISSION_UPDATED:    'Mission mise à jour',
            MISSION_CANCELLED:  'Mission annulée',
        };

        await NotificationModel.create({
            userId:   profile.userId,
            role:     'technician',
            type,
            title:    titles[type] || 'Notification mission',
            body:     `${mission.title} — Machine: ${mission.machineName || mission.machineId}`,
            missionId: mission.id,
        });
    } catch (_) {}
}

// ─── Admin / Concepteur ───────────────────────────────────────────────────────

/**
 * GET /api/missions
 * Liste toutes les missions (admin/concepteur) ou filtrées.
 * Query : status, technicianId, machineId
 */
async function listAll(req, res) {
    try {
        const { status, technicianId, machineId } = req.query;
        const rows = await MissionModel.listAll({ status, technicianId, machineId });
        res.set('Cache-Control', 'no-store');
        return res.json(rows.map(serializeMission));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * GET /api/missions/:id
 */
async function getOne(req, res) {
    try {
        const id  = parseInt(req.params.id, 10);
        const row = await MissionModel.getById(id);
        if (!row) return res.status(404).json({ error: 'Mission introuvable' });
        return res.json(serializeMission(row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * POST /api/missions
 * Créer et assigner une mission à un technicien.
 * Body : { technicianId, machineId, title, description?, priority?, scheduledAt? }
 */
async function create(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        const {
            technicianId, machineId, title,
            description = '', priority = 'NORMAL',
            scheduledAt,
        } = req.body;

        if (!technicianId) return res.status(400).json({ error: 'technicianId est obligatoire' });
        if (!machineId)    return res.status(400).json({ error: 'machineId est obligatoire' });
        if (!title)        return res.status(400).json({ error: 'title est obligatoire' });

        // Vérifier technicien et machine
        const techProfile = await prisma.technician.findFirst({ where: { technicianId } });
        if (!techProfile) return res.status(404).json({ error: 'Technicien introuvable' });

        const machine = await prisma.machine.findUnique({ where: { id: machineId } });
        if (!machine) return res.status(404).json({ error: 'Machine introuvable' });

        const mission = await MissionModel.create({
            missionId:   nextBusinessId('MIS'),
            technicianId,
            machineId,
            machineName: machine.name,
            title,
            description,
            priority,
            status:      'PENDING',
            scheduledAt: scheduledAt ? new Date(scheduledAt) : null,
            createdById: userId || null,
        });

        // Notifier le technicien
        notifyTechnician(mission, 'MISSION_ASSIGNED').catch(console.error);

        return res.status(201).json(serializeMission(mission));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * PUT /api/missions/:id
 * Modifier une mission.
 */
async function update(req, res) {
    try {
        const id       = parseInt(req.params.id, 10);
        const existing = await MissionModel.getById(id);
        if (!existing) return res.status(404).json({ error: 'Mission introuvable' });

        const {
            title, description, priority,
            status, scheduledAt,
        } = req.body;

        const data = {};
        if (title       !== undefined) data.title       = title;
        if (description !== undefined) data.description = description;
        if (priority    !== undefined) data.priority    = priority;
        if (status      !== undefined) {
            data.status = status;
            if (status === 'DONE') data.completedAt = new Date();
        }
        if (scheduledAt !== undefined) data.scheduledAt = scheduledAt ? new Date(scheduledAt) : null;

        const updated = await MissionModel.update(id, data);

        const notifType = status === 'CANCELLED' ? 'MISSION_CANCELLED' : 'MISSION_UPDATED';
        notifyTechnician(updated, notifType).catch(console.error);

        return res.json(serializeMission(updated));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * DELETE /api/missions/:id
 */
async function remove(req, res) {
    try {
        const id       = parseInt(req.params.id, 10);
        const existing = await MissionModel.getById(id);
        if (!existing) return res.status(404).json({ error: 'Mission introuvable' });

        await notifyTechnician(existing, 'MISSION_CANCELLED');
        await MissionModel.remove(id);
        return res.json({ success: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── Self (technicien connecté) ───────────────────────────────────────────────

/**
 * GET /api/missions/me
 * Missions du technicien connecté.
 */
async function listMine(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        const profile = await prisma.technician.findUnique({ where: { userId } });
        if (!profile) return res.status(404).json({ error: 'Profil technicien introuvable' });

        const { status, priority } = req.query;
        const rows = await MissionModel.listByTechnician(profile.technicianId, { status, priority });

        res.set('Cache-Control', 'no-store');
        return res.json(rows.map(serializeMission));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * GET /api/missions/me/sidebar
 * Données optimisées pour la sidebar Flutter du technicien.
 * Renvoie les missions groupées par statut + compteurs.
 */
async function getSidebarData(req, res) {
    try {
        const userId  = getAuthUserId(req.auth);
        const profile = await prisma.technician.findUnique({ where: { userId } });
        if (!profile) return res.status(404).json({ error: 'Profil technicien introuvable' });

        const all = await MissionModel.listByTechnician(profile.technicianId);

        const grouped = {
            PENDING:     [],
            IN_PROGRESS: [],
            DONE:        [],
            CANCELLED:   [],
        };

        for (const m of all) {
            const status = m.status in grouped ? m.status : 'PENDING';
            grouped[status].push(serializeMission(m));
        }

        const counts = {
            total:      all.length,
            pending:    grouped.PENDING.length,
            inProgress: grouped.IN_PROGRESS.length,
            done:       grouped.DONE.length,
            cancelled:  grouped.CANCELLED.length,
            urgent:     all.filter(m => m.priority === 'URGENT').length,
        };

        res.set('Cache-Control', 'no-store');
        return res.json({ counts, grouped });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * PATCH /api/missions/me/:id/status
 * Le technicien change le statut de sa propre mission.
 * Body : { status: "IN_PROGRESS" | "DONE" | "CANCELLED" }
 */
async function updateMyMissionStatus(req, res) {
    try {
        const userId  = getAuthUserId(req.auth);
        const profile = await prisma.technician.findUnique({ where: { userId } });
        if (!profile) return res.status(404).json({ error: 'Profil technicien introuvable' });

        const id       = parseInt(req.params.id, 10);
        const existing = await MissionModel.getById(id);
        if (!existing) return res.status(404).json({ error: 'Mission introuvable' });

        // Vérifier que la mission appartient bien au technicien connecté
        if (existing.technicianId !== profile.technicianId) {
            return res.status(403).json({ error: 'Cette mission ne vous appartient pas' });
        }

        const { status } = req.body;
        if (!['IN_PROGRESS', 'DONE', 'CANCELLED'].includes(status)) {
            return res.status(400).json({ error: 'Statut invalide' });
        }

        const data = { status };
        if (status === 'DONE') data.completedAt = new Date();

        const updated = await MissionModel.update(id, data);
        return res.json(serializeMission(updated));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = {
    listAll,
    getOne,
    create,
    update,
    remove,
    listMine,
    getSidebarData,
    updateMyMissionStatus,
};
