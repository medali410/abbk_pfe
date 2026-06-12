// src/routes/missions.js
const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const ctrl = require('../controllers/missionController');

const router = express.Router();

// ─── Self routes (technicien connecté) ───────────────────────────────────────
// ⚠️  Ces routes doivent être AVANT /:id
router.get('/me',               requireAuth, ctrl.listMine);
router.get('/me/sidebar',       requireAuth, ctrl.getSidebarData);
router.patch('/me/:id/status',  requireAuth, ctrl.updateMyMissionStatus);

// ─── Routes admin / fleet manager ─────────────────────────────────────────────
router.get('/',                 requireAuth, requireFleetManager, ctrl.listAll);
router.post('/',                requireAuth, requireFleetManager, ctrl.create);
router.get('/:id',              requireAuth, ctrl.getOne);
router.put('/:id',              requireAuth, requireFleetManager, ctrl.update);
router.delete('/:id',           requireAuth, requireFleetManager, ctrl.remove);

module.exports = router;
