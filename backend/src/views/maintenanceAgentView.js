// src/views/maintenanceAgentView.js
const { mergeUserProfile } = require('./userView');

/**
 * Sérialise un profil MaintenanceAgent + User.
 * Même pattern que les autres views du projet (userView, machineView, documentView).
 *
 * @param {object} user    — enregistrement User Prisma
 * @param {object} profile — enregistrement MaintenanceAgent Prisma
 * @returns {object}
 */
function serializeMaintenanceAgent(user, profile) {
    return mergeUserProfile(user, profile, {
        maintenanceAgentId: profile.maintenanceAgentId,
        firstName:          profile.firstName,
        lastName:           profile.lastName,
        name:               `${profile.firstName} ${profile.lastName}`.trim() || user.nom,
        clientId:           profile.clientId,
    });
}

/**
 * Sérialise le tableau de bord de l'agent connecté.
 * Inclut le profil + ses machines assignées + stats + télémétries + demandes récentes.
 *
 * @param {object}   user             — enregistrement User Prisma
 * @param {object}   profile          — enregistrement MaintenanceAgent Prisma
 * @param {object[]} machines         — machines assignées
 * @param {object}   telemetryMap     — { [machineId]: dernierEnregistrementTelemetry }
 * @param {object[]} purchaseRequests — dernières PurchaseRequest liées au clientId
 * @returns {object}
 */
function serializeMaintenanceAgentDashboard(
    user,
    profile,
    machines = [],
    telemetryMap = {},
    purchaseRequests = [],
) {
    const base = serializeMaintenanceAgent(user, profile);
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
        recentPurchaseRequests: purchaseRequests,
    };
}

module.exports = { serializeMaintenanceAgent, serializeMaintenanceAgentDashboard };
