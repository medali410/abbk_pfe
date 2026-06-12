// src/routes/controles.js
const express = require('express');
const router = express.Router();
const controleController = require('../controllers/controleController');

// Mettre le middleware d'authentification ici si nécessaire, 
// ex: const { requireAuth } = require('../middlewares/auth');
// router.use(requireAuth);

router.get('/', controleController.getControles);
router.get('/machine/:id', controleController.getControlesForMachine);
router.get('/technicien/:id', controleController.getControlesForTechnician);

router.post('/terrain', controleController.submitControleCalendrierSaisie);
router.get('/calendrier-journal', controleController.getControlCalendrierJournal);

router.put('/:id/statut', controleController.updateControleStatus);
router.patch('/:id/assign', controleController.assignControleToTechnician);

router.get('/preventive-history', controleController.getPreventiveHistory);

module.exports = router;
