const fs = require('fs');

let content = fs.readFileSync('dali-pfe/lib/add_maintenance_agent_page.dart', 'utf-8');

// Replacements
content = content.replace(/AddMaintenanceAgentPage/g, 'AddTechnicianPage');
content = content.replace(/_AddMaintenanceAgentPageState/g, '_AddTechnicianPageState');
content = content.replace(/MaintenanceAgent/g, 'Technician');
content = content.replace(/maintenanceAgentId/g, 'technicianId');
content = content.replace(/clientId/g, 'companyId');
content = content.replace(/maintenance/g, 'technician');
content = content.replace(/Maintenance/g, 'Technician');
content = content.replace(/Nom complet technicien/g, 'Nom complet technicien');
content = content.replace(/onEmbeddedBack/g, 'onBack');

// Need to replace the ApiService calls!
// ApiService.addTechnician
// ApiService.updateTechnician
// Wait, the python/node script already handles "addMaintenanceAgent" -> "addTechnician" because of "Maintenance" -> "Technician".
// Let's verify: "addMaintenanceAgent" -> "addTechnicianAgent"? 
// Ah! "addMaintenanceAgent".replace("Maintenance", "Technician") -> "addTechnicianAgent".
// That's wrong, we need "addTechnician".
content = content.replace(/addTechnicianAgent/g, 'addTechnician');
content = content.replace(/updateTechnicianAgent/g, 'updateTechnician');
content = content.replace(/_AddTechnicianAgentPageState/g, '_AddTechnicianPageState');
content = content.replace(/TechnicianAgent/g, 'Technician');

// Write to file
fs.writeFileSync('dali-pfe/lib/add_technician_page.dart', content, 'utf-8');
console.log('Done');
