// src/views/notificationView.js

function serializeNotification(row) {
    if (!row) return null;
    return {
        id:             row.id,
        userId:         row.userId,
        role:           row.role,
        type:           row.type,
        title:          row.title,
        body:           row.body,
        isRead:         row.isRead,
        consultationId: row.consultationId ?? null,
        missionId:      row.missionId ?? null,
        createdAt:      row.createdAt,
    };
}

module.exports = { serializeNotification };
