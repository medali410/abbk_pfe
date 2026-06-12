// src/views/technicianView.js
const { mergeUserProfile } = require('./userView');

/**
 * Sérialise un profil Technician + User.
 * Même pattern que les autres views du projet (userView, machineView, documentView).
 *
 * @param {object} user    — enregistrement User Prisma
 * @param {object} profile — enregistrement Technician Prisma
 * @returns {object}
 */
function serializeTechnician(user, profile) {
    return mergeUserProfile(user, profile, {
        technicianId:   profile.technicianId,
        firstName:      profile.firstName,
        lastName:       profile.lastName,
        name:           `${profile.firstName} ${profile.lastName}`.trim() || user.nom,
        specialization: profile.specialization,
        status:         profile.status,
        companyId:      profile.companyId,
    });
}

/**
 * Sérialise le tableau de bord du technicien connecté.
 * Inclut le profil + ses machines assignées + stats + dernières télémétries.
 *
 * @param {object}   user         — enregistrement User Prisma
 * @param {object}   profile      — enregistrement Technician Prisma
 * @param {object[]} machines     — machines assignées (depuis Machine Prisma)
 * @param {object}   telemetryMap — { [machineId]: dernierEnregistrementTelemetry }
 * @returns {object}
 */
function serializeTechnicianDashboard(user, profile, machines = [], telemetryMap = {}) {
    const base = serializeTechnician(user, profile);
    const stats = {
        totalMachines:   machines.length,
        runningMachines: machines.filter(m => m.status === 'RUNNING').length,
        stoppedMachines: machines.filter(m => m.status === 'STOPPED').length,
        errorMachines:   machines.filter(m => m.status === 'ERROR').length,
    };
    return {
        ...base,
        machines: machines.map(m => ({
            ...m,
            latestTelemetry: telemetryMap[m.id] || null,
        })),
        stats,
    };
}

module.exports = { serializeTechnician, serializeTechnicianDashboard };
