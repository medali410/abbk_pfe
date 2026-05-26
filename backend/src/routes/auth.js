const express = require('express');
const authController = require('../controllers/authController');

const router = express.Router();

router.post('/login', authController.login);
router.get('/auth/google/status', authController.googleStatus);
router.get('/auth/google/start', authController.googleStart);
router.get('/auth/google/callback', authController.googleCallback);
router.post('/client-google-auth', authController.clientGoogleAuth);
router.post('/client-self-register', authController.clientSelfRegister);
router.post('/maintenance-login', authController.maintenanceLogin);

module.exports = router;
