const { signToken } = require('../lib/jwtToken');

function parseJsonArray(str) {
    try {
        const v = JSON.parse(str || '[]');
        return Array.isArray(v) ? v : [];
    } catch {
        return [];
    }
}

function mergeUserProfile(user, profile, extra = {}) {
    if (!user) return null;
    const base = {
        id: String(profile?.clientId || profile?.technicianId || profile?.maintenanceAgentId || user.id),
        userId: user.id,
        email: user.email,
        nom: user.nom,
        name: user.nom,
        adresse: user.adresse,
        role: user.role,
        ...extra,
    };
    if (profile?.clientId) base.clientId = profile.clientId;
    if (profile?.technicianId) base.technicianId = profile.technicianId;
    if (profile?.maintenanceAgentId) base.maintenanceAgentId = profile.maintenanceAgentId;
    if (profile?.location != null) base.location = profile.location;
    if (profile?.motorType != null) base.motorType = profile.motorType;
    if (profile?.specialite != null) base.specialite = profile.specialite;
    if (profile?.companyId != null) base.companyId = profile.companyId;
    if (profile?.machineIds != null) base.machineIds = parseJsonArray(profile.machineIds);
    return base;
}

function loginResponse(user, profileExtra = {}) {
    return {
        token: signToken(user),
        role: user.role,
        email: user.email,
        nom: user.nom,
        name: user.nom,
        adresse: user.adresse,
        id: String(user.id),
        ...profileExtra,
    };
}

module.exports = { mergeUserProfile, loginResponse, parseJsonArray };
