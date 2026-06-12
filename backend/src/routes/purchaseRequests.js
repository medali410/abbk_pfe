const express = require('express');
const { requireAuth } = require('../lib/auth');
const purchaseRequestController = require('../controllers/purchaseRequestController');

const router = express.Router();

router.post('/', purchaseRequestController.create);
router.get('/', requireAuth, purchaseRequestController.list);
router.patch('/:id/status', requireAuth, purchaseRequestController.updateStatus);
router.post('/:id/provision-team', requireAuth, purchaseRequestController.provisionTeam);

module.exports = router;
