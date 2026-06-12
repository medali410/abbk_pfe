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
        imageUrl: m.imageUrl || '',
        isPublic: m.isPublic !== false,
        concepteurId: m.concepteurId || '',
        wifiSsid: m.wifiSsid || '',
        wifiPassword: m.wifiPassword || '',
        price: m.price || '',
        stock: m.stock || 0,
        createdAt: m.createdAt,
        updatedAt: m.updatedAt,
    };
}

module.exports = { serializeMachine };
