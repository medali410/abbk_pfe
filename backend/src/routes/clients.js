const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const clientController = require('../controllers/clientController');

const router = express.Router();

router.get('/', requireAuth, clientController.list);
router.post('/', requireAuth, requireFleetManager, clientController.create);
router.get('/:id', requireAuth, requireFleetManager, clientController.getById);
router.put('/:id', requireAuth, requireFleetManager, clientController.update);
router.delete('/:id', requireAuth, requireFleetManager, clientController.remove);
router.get('/:id/machines', requireAuth, clientController.getMachines);
router.get('/:id/technicians', requireAuth, clientController.getTechnicians);
router.get('/:id/maintenance-agents', requireAuth, clientController.getMaintenanceAgents);


module.exports = router;
