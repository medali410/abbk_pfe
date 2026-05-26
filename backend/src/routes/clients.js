const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const clientController = require('../controllers/clientController');

const router = express.Router();

router.get('/', requireAuth, requireFleetManager, clientController.list);
router.post('/', requireAuth, requireFleetManager, clientController.create);
router.get('/:id', requireAuth, requireFleetManager, clientController.getById);
router.put('/:id', requireAuth, requireFleetManager, clientController.update);
router.delete('/:id', requireAuth, requireFleetManager, clientController.remove);
router.get('/:id/machines', requireAuth, requireFleetManager, clientController.getMachines);


module.exports = router;
