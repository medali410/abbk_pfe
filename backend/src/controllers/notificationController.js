// src/controllers/notificationController.js
/**
 * Notifications pour l'utilisateur connecté.
 * Chaque utilisateur ne voit que ses propres notifications.
 */

const NotificationModel = require('../models/notificationModel');
const { serializeNotification } = require('../views/notificationView');
const { getAuthUserId } = require('../lib/auth');

/**
 * GET /api/notifications
 * Liste les notifications de l'utilisateur connecté.
 */
async function list(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const rows  = await NotificationModel.listForUser(userId);
        const unread = await NotificationModel.countUnread(userId);

        res.set('Cache-Control', 'no-store');
        return res.json({
            unreadCount:   unread,
            notifications: rows.map(serializeNotification),
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * PATCH /api/notifications/:id/read
 * Marque une notification comme lue.
 */
async function markRead(req, res) {
    try {
        const id      = parseInt(req.params.id, 10);
        const updated = await NotificationModel.markRead(id);
        return res.json(serializeNotification(updated));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * PATCH /api/notifications/read-all
 * Marque toutes les notifications comme lues.
 */
async function markAllRead(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        await NotificationModel.markAllRead(userId);
        return res.json({ success: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/**
 * DELETE /api/notifications/:id
 * Supprime une notification.
 */
async function remove(req, res) {
    try {
        const id = parseInt(req.params.id, 10);
        await NotificationModel.remove(id);
        return res.json({ success: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = { list, markRead, markAllRead, remove };
