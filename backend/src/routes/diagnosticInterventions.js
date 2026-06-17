// src/routes/diagnosticInterventions.js
const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/diagnosticInterventionController');
const { requireAuth } = require('../lib/auth');

router.get('/', requireAuth, ctrl.getDiagnosticInterventions);
router.get('/:id', requireAuth, ctrl.getOneDiagnosticIntervention);
router.post('/', requireAuth, ctrl.createDiagnosticIntervention);
router.post('/:id/messages', requireAuth, ctrl.addMessage);
router.post('/:id/coordination', requireAuth, ctrl.addCoordination);
router.patch('/:id/coordination/:noteId/status', requireAuth, ctrl.updateCoordinationStatus);
router.patch('/:id/messages/:messageId/status', requireAuth, ctrl.updateMessageStatus);

module.exports = router;
