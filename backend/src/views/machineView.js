function serializeMachine(m) {
    if (!m) return null;
    return {
        id: m.id,
        _id: m.id,
        machineId: m.id,
        name: m.name,
        type: m.type,
        disponible: m.disponible,
        status: m.status,
        companyId: m.companyId || '',
        motorType: m.motorType,
        location: m.location || '',
        model3dUrl: m.model3dUrl || '',
        modele3dId: m.modele3dId,
        createdAt: m.createdAt,
        updatedAt: m.updatedAt,
    };
}

module.exports = { serializeMachine };
