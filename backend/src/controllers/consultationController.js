// src/controllers/consultationController.js
/**
 * Gestion des consultations de machines par le technicien.
 * Quand une consultation est créée, des notifications sont envoyées
 * automatiquement au client et à l'agent de maintenance concernés.
 */

const ConsultationModel  = require('../models/consultationModel');
const NotificationModel  = require('../models/notificationModel');
const { serializeConsultation } = require('../views/consultationView');
const { getAuthUserId }  = require('../lib/auth');
const { nextBusinessId } = require('../lib/ids');
const { prisma }         = require('../lib/prisma');

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Résout le userId depuis un rôle + identifiant métier.
 * Retourne null si introuvable (pas bloquant — la notif est ignorée).
 */
async function resolveUserId(role, businessId) {
    if (!businessId) return null;
    try {
        if (role === 'client') {
            const row = await prisma.client.findUnique({ where: { clientId: businessId } });
            return row?.userId ?? null;
        }
        if (role === 'maintenance') {
            const row = await prisma.maintenanceAgent.findUnique({ where: { maintenanceAgentId: businessId } });
            return row?.userId ?? null;
        }
    } catch (_) {}
    return null;
}

/**
 * Envoie les notifications au client et à l'agent après création/modification.
 */
async function dispatchNotifications(consultation, type = 'CONSULTATION_SCHEDULED') {
    const notifications = [];

    const titles = {
        CONSULTATION_SCHEDULED: 'Nouvelle consultation planifiée',
        CONSULTATION_UPDATED:   'Consultation mise à jour',
        CONSULTATION_CANCELLED: 'Consultation annulée',
        CONSULTATION_CONFIRMED: 'Consultation confirmée',
    };

    const body = `Machine ${consultation.machineId} — ${new Date(consultation.scheduledDate).toLocaleString('fr-FR')}`;
    const title = titles[type] || 'Notification consultation';

    // Notification → Client
    const clientUserId = await resolveUserId('client', consultation.clientId);
    if (clientUserId) {
        notifications.push({
            userId:         clientUserId,
            role:           'client',
            type,
            title,
            body,
            consultationId: consultation.id,
        });
    }

    // Notification → Agent de maintenance
    const agentUserId = await resolveUserId('maintenance', consultation.maintenanceAgentId);
    if (agentUserId) {
        notifications.push({
            userId:         agentUserId,
            role:           'maintenance',
            type,
            title,
            body,
            consultationId: consultation.id,
        });
    }

    if (notifications.length > 0) {
        await NotificationModel.createMany(notifications);
    }
}

// ─── Controllers ─────────────────────────────────────────────────────────────

/**
 * GET /api/consultations
 * - Technicien connecté → ses propres consultations
 * - Admin/Concepteur   → toutes (ou filtrées par technicianId query)
 */
async function list(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        const role   = String(req.auth?.role || '').toLowerCase();
        const { status, technicianId } = req.query;

        let rows;
        if (role === 'technician') {
            const profile = await prisma.technician.findUnique({ where: { userId } });
            if (!profile) return res.status(404).json({ error: 'Profil technicien introuvable' });
            rows = await ConsultationModel.listByTechnician(profile.technicianId, { status });
        } else if (role === 'client') {
            const profile = await prisma.client.findUnique({ where: { userId } });
            if (!profile) return res.status(404).json({ error: 'Profil client introuvable' });
            rows = await ConsultationModel.listByClient(profile.clientId);
        } else if (role === 'maintenance') {
            const profile = await prisma.maintenanceAgent.findUnique({ where: { userId } });
            if (!profile) return res.status(404).json({ error: 'Profil agent introuvable' });
            rows = await ConsultationModel.listByMaintenanceAgent(profile.maintenanceAgentId);
        } else {
            // admin / conception → tout
            const where = {};
            if (status)       where.status       = status;
            if (technicianId) where.technicianId = technicianId;
            rows = await prisma.consultation.findMany({
                where,
                orderBy: { scheduledDate: 'asc' },
            });
        }

        res.set('Cache-Control', 'no-store');
        return res.json(rows.map(serializeConsultation));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * GET /api/consultations/:id
 */
async function getOne(req, res) {
    try {
        const id  = parseInt(req.params.id, 10);
        const row = await ConsultationModel.getById(id);
        if (!row) return res.status(404).json({ error: 'Consultation introuvable' });
        return res.json(serializeConsultation(row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * POST /api/consultations
 * Le technicien crée une consultation en choisissant une date (drag-and-drop).
 * Body : {
 *   machineId, scheduledDate, durationMinutes?,
 *   note?, clientId, maintenanceAgentId
 * }
 */
async function create(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        const role   = String(req.auth?.role || '').toLowerCase();

        // Résoudre le technicianId métier depuis l'utilisateur connecté
        let technicianId;
        if (role === 'technician') {
            const profile = await prisma.technician.findUnique({ where: { userId } });
            if (!profile) return res.status(404).json({ error: 'Profil technicien introuvable' });
            technicianId = profile.technicianId;
        } else {
            // Admin peut créer au nom d'un technicien
            technicianId = req.body.technicianId;
            if (!technicianId) return res.status(400).json({ error: 'technicianId est obligatoire' });
        }

        const {
            machineId, scheduledDate,
            durationMinutes = 60, note = '',
            clientId = '', maintenanceAgentId = '',
        } = req.body;

        if (!machineId)     return res.status(400).json({ error: 'machineId est obligatoire' });
        if (!scheduledDate) return res.status(400).json({ error: 'scheduledDate est obligatoire' });

        // Vérifier que la machine existe
        const machine = await prisma.machine.findUnique({ where: { id: machineId } });
        if (!machine) return res.status(404).json({ error: 'Machine introuvable' });

        const consultation = await ConsultationModel.create({
            consultationId:     nextBusinessId('CON'),
            machineId,
            technicianId,
            scheduledDate:      new Date(scheduledDate),
            durationMinutes,
            note,
            clientId,
            maintenanceAgentId,
            status:             'PENDING',
        });

        // Notifications asynchrones (pas bloquant)
        dispatchNotifications(consultation, 'CONSULTATION_SCHEDULED').catch(console.error);

        return res.status(201).json(serializeConsultation(consultation));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * PUT /api/consultations/:id
 * Modifier la date ou les infos d'une consultation.
 */
async function update(req, res) {
    try {
        const id       = parseInt(req.params.id, 10);
        const existing = await ConsultationModel.getById(id);
        if (!existing) return res.status(404).json({ error: 'Consultation introuvable' });

        const {
            scheduledDate, durationMinutes, note,
            status, clientId, maintenanceAgentId,
        } = req.body;

        const data = {};
        if (scheduledDate      !== undefined) data.scheduledDate      = new Date(scheduledDate);
        if (durationMinutes    !== undefined) data.durationMinutes    = durationMinutes;
        if (note               !== undefined) data.note               = note;
        if (status             !== undefined) data.status             = status;
        if (clientId           !== undefined) data.clientId           = clientId;
        if (maintenanceAgentId !== undefined) data.maintenanceAgentId = maintenanceAgentId;

        const updated = await ConsultationModel.update(id, data);

        // Notifier si date ou statut changé
        const notifType = status === 'CANCELLED' ? 'CONSULTATION_CANCELLED'
                        : status === 'CONFIRMED'  ? 'CONSULTATION_CONFIRMED'
                        : 'CONSULTATION_UPDATED';
        dispatchNotifications(updated, notifType).catch(console.error);

        return res.json(serializeConsultation(updated));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * DELETE /api/consultations/:id
 */
async function remove(req, res) {
    try {
        const id       = parseInt(req.params.id, 10);
        const existing = await ConsultationModel.getById(id);
        if (!existing) return res.status(404).json({ error: 'Consultation introuvable' });

        // Notifier annulation avant suppression
        await dispatchNotifications(existing, 'CONSULTATION_CANCELLED');
        await ConsultationModel.remove(id);

        return res.json({ success: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = { list, getOne, create, update, remove };
