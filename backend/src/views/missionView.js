// src/views/missionView.js

const PRIORITY_ORDER = { URGENT: 4, HIGH: 3, NORMAL: 2, LOW: 1 };

function serializeMission(row) {
    if (!row) return null;
    return {
        id:            row.id,
        missionId:     row.missionId,
        technicianId:  row.technicianId,
        machineId:     row.machineId,
        machineName:   row.machineName,
        title:         row.title,
        description:   row.description,
        priority:      row.priority,
        priorityOrder: PRIORITY_ORDER[row.priority] ?? 2,
        status:        row.status,
        scheduledAt:   row.scheduledAt ?? null,
        completedAt:   row.completedAt ?? null,
        createdById:   row.createdById ?? null,
        createdAt:     row.createdAt,
        updatedAt:     row.updatedAt,
    };
}

module.exports = { serializeMission };
