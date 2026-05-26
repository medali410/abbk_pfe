const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const documentController = require('../controllers/documentController');

const router = express.Router();

router.get('/', requireAuth, requireFleetManager, documentController.list);
router.post('/', requireAuth, requireFleetManager, documentController.create);

module.exports = router;
