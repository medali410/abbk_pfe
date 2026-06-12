// src/routes/maintenanceAgents.js
const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const ctrl = require('../controllers/maintenanceAgentController');

const router = express.Router();

// ─── Self routes (agent connecté) ─────────────────────────────────────────────
// ⚠️  Ces routes doivent être AVANT /:id pour que "me" ne soit pas capturé comme un id.
router.get('/me',                         requireAuth, ctrl.getMyProfile);
router.patch('/me',                       requireAuth, ctrl.updateMyProfile);
router.get('/me/telemetry',               requireAuth, ctrl.getMyMachinesTelemetry);
router.post('/me/purchase-requests',      requireAuth, ctrl.submitPurchaseRequest);

// ─── Routes admin / fleet manager ─────────────────────────────────────────────
router.get('/',                           requireAuth, ctrl.listMaintenanceAgents);
router.post('/',                          requireAuth, requireFleetManager, ctrl.createMaintenanceAgent);
router.get('/:id',                        requireAuth, requireFleetManager, ctrl.getMaintenanceAgent);
router.put('/:id',                        requireAuth, requireFleetManager, ctrl.updateMaintenanceAgent);
router.delete('/:id',                     requireAuth, requireFleetManager, ctrl.deleteMaintenanceAgent);
router.patch('/:id/machines',             requireAuth, requireFleetManager, ctrl.assignMachines);

module.exports = router;
