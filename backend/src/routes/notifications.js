// src/routes/notifications.js
const express = require('express');
const { requireAuth } = require('../lib/auth');
const ctrl = require('../controllers/notificationController');

const router = express.Router();

// ⚠️  read-all AVANT /:id pour éviter que "read-all" soit capturé comme un id
router.get('/',                requireAuth, ctrl.list);
router.patch('/read-all',      requireAuth, ctrl.markAllRead);
router.patch('/:id/read',      requireAuth, ctrl.markRead);
router.delete('/:id',          requireAuth, ctrl.remove);

module.exports = router;
