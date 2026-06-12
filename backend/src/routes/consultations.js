// src/routes/consultations.js
const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const ctrl = require('../controllers/consultationController');

const router = express.Router();

// Tous les rôles authentifiés peuvent voir leurs consultations
router.get('/',      requireAuth, ctrl.list);
router.get('/:id',   requireAuth, ctrl.getOne);

// Technicien + Admin/Concepteur peuvent créer
router.post('/',     requireAuth, ctrl.create);

// Mise à jour — technicien pour sa propre consultation, admin pour toutes
router.put('/:id',   requireAuth, ctrl.update);

// Suppression — fleet manager seulement
router.delete('/:id', requireAuth, requireFleetManager, ctrl.remove);

module.exports = router;
