// src/views/consultationView.js

function serializeConsultation(row) {
    if (!row) return null;
    return {
        id:                 row.id,
        consultationId:     row.consultationId,
        machineId:          row.machineId,
        technicianId:       row.technicianId,
        scheduledDate:      row.scheduledDate,
        durationMinutes:    row.durationMinutes,
        status:             row.status,
        note:               row.note,
        clientId:           row.clientId,
        maintenanceAgentId: row.maintenanceAgentId,
        createdAt:          row.createdAt,
        updatedAt:          row.updatedAt,
    };
}

module.exports = { serializeConsultation };
