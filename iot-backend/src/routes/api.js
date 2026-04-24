const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');
const machineController = require('../controllers/machineController');
const telemetryController = require('../controllers/telemetryController');
const alertController = require('../controllers/alertController');
const companyController = require('../controllers/companyController');
const userController = require('../controllers/userController');
const maintenanceController = require('../controllers/maintenanceController');
const aiController = require('../controllers/aiController');
const conceptionController = require('../controllers/conceptionController');
const terminalController = require('../controllers/terminalController');
const collaborationController = require('../controllers/collaborationController');



// Auth Routes
router.post('/auth/login', authController.login);
router.post('/auth/register', authController.register);

// AI Routes
router.post('/ai/chat', aiController.chat);

// Machine Routes
router.get('/machines', machineController.getAllMachines);
router.get('/machines/:id', machineController.getMachineById);
router.post('/machines', machineController.createMachine);
router.put('/machines/:id', machineController.updateMachine);
router.put('/machines/:id/parameters', machineController.updateMachineParameters);
router.post('/machines/:id/status', machineController.updateMachineStatus); // Used by n8n
router.delete('/machines/:id', machineController.deleteMachine);

// Telemetry Routes
router.post('/telemetry', telemetryController.addTelemetry);
router.get('/telemetry/:machineId', telemetryController.getLatestTelemetry);
router.get('/telemetry/:machineId/history', telemetryController.getHistory);

// Alert Routes
router.get('/alerts', alertController.getAllAlerts);
router.get('/alerts/stats', alertController.getAlertStats);
router.get('/alerts/machine/:machineId', alertController.getAlertsByMachine);
router.post('/alerts', alertController.createAlert);
router.put('/alerts/:id/resolve', alertController.resolveAlert);
router.delete('/alerts/:id', alertController.deleteAlert);

// Company Routes
router.get('/companies', companyController.getAllCompanies);
router.post('/companies', companyController.createCompany);
router.put('/companies/:id', companyController.updateCompany);
router.delete('/companies/:id', companyController.deleteCompany);

// User/Technician routes
router.get('/users', userController.getAllUsers);
router.post('/users', userController.createUser);
router.put('/users/:id', userController.updateUser);
router.delete('/users/:id', userController.deleteUser);

// Maintenance Routes
router.get('/maintenance', maintenanceController.getOrders);
router.post('/maintenance', maintenanceController.createOrder);
router.put('/maintenance/:id', maintenanceController.updateOrderStatus);
router.patch('/maintenance/:id', maintenanceController.updateOrder);
router.delete('/maintenance/:id', maintenanceController.deleteOrder);
router.post('/maintenance/request', maintenanceController.requestControl);

// Diagnostic Intervention Routes
router.get('/diagnostic-interventions', maintenanceController.getDiagnosticInterventions);
router.post('/diagnostic-interventions', maintenanceController.createDiagnosticIntervention);
router.post('/diagnostic-interventions/:id/messages', maintenanceController.addDiagnosticMessage);
router.post('/diagnostic-interventions/:id/steps', maintenanceController.addDiagnosticStep);
router.post('/diagnostic-interventions/:id/steps/:stepId/ok', maintenanceController.markDiagnosticStepOk);
router.post('/diagnostic-interventions/:id/next', maintenanceController.nextDiagnosticStep);
router.patch('/diagnostic-interventions/:id/decision', maintenanceController.setDiagnosticDecision);
router.patch('/diagnostic-interventions/:id/status', maintenanceController.updateDiagnosticStatus);
router.delete('/diagnostic-interventions/:id', maintenanceController.deleteDiagnosticIntervention);
router.patch('/diagnostic-interventions/:id/reassign', maintenanceController.reassignTechnician);

// Conception Routes
router.get('/conceptions', conceptionController.getAllConceptions);
router.post('/conceptions', conceptionController.createConception);

// Terminal Routes
router.get('/terminal/data', terminalController.getTerminalData);

// Collaboration Routes
router.get('/collaboration/data', collaborationController.getCollaborationData);



module.exports = router;
