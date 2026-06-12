import re

with open('dali-pfe/lib/add_maintenance_agent_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replacements
content = content.replace('AddMaintenanceAgentPage', 'AddTechnicianPage')
content = content.replace('_AddMaintenanceAgentPageState', '_AddTechnicianPageState')
content = content.replace('MaintenanceAgent', 'Technician')
content = content.replace('Maintenance Agent', 'Technicien')
content = content.replace('Maintenance', 'Technicien')
content = content.replace('maintenance', 'technicien')
content = content.replace('maintenanceAgentId', 'technicianId')
content = content.replace('clientId', 'companyId')
content = content.replace('Add Technicien', 'Nouveau Technicien')
content = content.replace('Edit Technicien', 'Modifier Technicien')

# specific fixes
content = content.replace('Nom complet technicien', 'Nom complet technicien')

with open('dali-pfe/lib/add_technician_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)
