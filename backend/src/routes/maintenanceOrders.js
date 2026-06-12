// src/routes/maintenanceOrders.js
const express = require('express');
const router = express.Router();
const controller = require('../controllers/maintenanceOrderController');

router.get('/', controller.getMaintenanceOrders);
router.post('/', controller.createMaintenanceOrder);
router.put('/:id', controller.updateMaintenanceOrder);
router.put('/:id/status', controller.updateMaintenanceOrderStatus);
// Allow GET /:id as well if the front end wants it. For now, it queries all via machineId.

module.exports = router;
