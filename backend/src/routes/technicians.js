// src/routes/technicians.js
const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const ctrl = require('../controllers/technicianController');

const router = express.Router();

// ─── Self routes (technicien connecté) ───────────────────────────────────────
// ⚠️  Ces routes doivent être AVANT /:id pour que "me" ne soit pas capturé comme un id.
router.get('/me',                requireAuth, ctrl.getMyProfile);
router.patch('/me',              requireAuth, ctrl.updateMyProfile);
router.get('/me/telemetry',      requireAuth, ctrl.getMyMachinesTelemetry);

// ─── Routes admin / fleet manager ─────────────────────────────────────────────
router.get('/',                  requireAuth, ctrl.listTechnicians);
router.post('/',                 requireAuth, requireFleetManager, ctrl.createTechnician);
router.get('/:id',               requireAuth, ctrl.getTechnician);
router.put('/:id',               requireAuth, requireFleetManager, ctrl.updateTechnician);
router.delete('/:id',            requireAuth, requireFleetManager, ctrl.deleteTechnician);
router.patch('/:id/machines',    requireAuth, requireFleetManager, ctrl.assignMachines);

module.exports = router;
