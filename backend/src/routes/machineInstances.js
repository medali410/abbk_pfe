const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const instanceCtrl = require('../controllers/machineInstanceController');

const router = express.Router();

router.get('/', requireAuth, instanceCtrl.listInstances);
router.post('/bulk-create', requireAuth, requireFleetManager, instanceCtrl.bulkCreateInstances);
router.get('/:instanceId', requireAuth, instanceCtrl.getInstance);
router.patch('/:instanceId/status', requireAuth, instanceCtrl.updateInstanceStatus);
router.patch('/:instanceId/config', requireAuth, instanceCtrl.configInstance);

module.exports = router;
