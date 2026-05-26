function serializeDocument(row) {
    if (!row) return null;
    return {
        id: row.documentId || String(row.id),
        documentId: row.documentId,
        _id: String(row.id),
        name: row.name,
        version: row.version,
        documentType: row.documentType,
        clientId: row.clientId,
        status: row.status,
        securityEmail: row.securityEmail,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
    };
}

module.exports = { serializeDocument };
