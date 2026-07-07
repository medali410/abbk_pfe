const { prisma } = require('../lib/prisma');

const RUNNING_STATUSES = new Set([
    // English variants
    'RUNNING', 'NORMAL', 'ONLINE', 'ACTIVE', 'WORKING', 'IN_WORK', 'IN_SERVICE',
    'OPERATIONAL', 'ENABLED', 'STARTED',
    // French variants (stored in DB)
    'EN_TRAVAIL', 'EN_MARCHE', 'EN_SERVICE', 'EN_PRODUCTION',
    'EN_FONCTIONNEMENT', 'EN_COURS', 'OPERATIONNEL',
]);
const HIGH_RISK_STATUSES = new Set([
    'FAILURE',
    'PANNE',
    'ALERT',
    'CRITICAL',
    'WARNING',
    'ERROR',
    'DEGRADED',
]);

const TN_CITY_POSITIONS = {
    tunis: { top: 0.22, left: 0.48 },
    ariana: { top: 0.2, left: 0.5 },
    ben_arous: { top: 0.26, left: 0.52 },
    bizerte: { top: 0.12, left: 0.42 },
    nabeul: { top: 0.28, left: 0.58 },
    hammamet: { top: 0.3, left: 0.56 },
    sousse: { top: 0.38, left: 0.55 },
    monastir: { top: 0.42, left: 0.58 },
    mahdia: { top: 0.48, left: 0.56 },
    sfax: { top: 0.55, left: 0.52 },
    gabes: { top: 0.68, left: 0.5 },
    gafsa: { top: 0.58, left: 0.38 },
    kairouan: { top: 0.4, left: 0.45 },
    tozeur: { top: 0.62, left: 0.28 },
};

function normalizeStatus(status) {
    return String(status || 'STOPPED')
        .trim()
        .toUpperCase()
        .replace(/[-\s]+/g, '_');
}

function isRunning(status) {
    return RUNNING_STATUSES.has(normalizeStatus(status));
}

function riskPctForMachine(machine) {
    if (machine.predictions && machine.predictions.length > 0) {
        const pct = machine.predictions[0].riskPercentage;
        if (typeof pct === 'number') return pct;
    }
    const s = normalizeStatus(machine.status);
    if (HIGH_RISK_STATUSES.has(s) || s.includes('FAIL') || s.includes('PANNE')) return 88;
    if (s.includes('WARN') || s.includes('ALERT')) return 62;
    if (isRunning(s)) return 18;
    if (s === 'STOPPED' || s === 'OFFLINE' || s === 'IDLE') return 8;
    return 25;
}

function dominantRiskMode(machines) {
    if (!machines.length) return 'Aucun risque majeur';
    const counts = {};
    for (const m of machines) {
        let label = '';
        if (m.predictions && m.predictions.length > 0) {
            label = m.predictions[0].typePanne;
        }
        if (!label || label === 'NORMAL' || label === 'NORMAL/RAS') {
            const s = normalizeStatus(m.status);
            if (HIGH_RISK_STATUSES.has(s) || s.includes('FAIL') || s.includes('PANNE')) {
                label = 'Panne / alerte critique';
            } else if (s.includes('WARN') || s.includes('ALERT')) {
                label = 'Surveillance renforcée';
            } else if (isRunning(s)) {
                label = 'Fonctionnement normal';
            } else {
                label = 'Machines à l’arrêt';
            }
        }
        counts[label] = (counts[label] || 0) + 1;
    }

    let bestLabel = 'Aucun risque majeur';
    let maxCount = -1;
    for (const [lbl, cnt] of Object.entries(counts)) {
        if (lbl === 'NORMAL' || lbl === 'NORMAL/RAS' || lbl.toLowerCase().includes('aucun')) {
            continue;
        }
        if (cnt > maxCount) {
            maxCount = cnt;
            bestLabel = lbl;
        }
    }
    if (bestLabel === 'Aucun risque majeur') {
        let maxAll = -1;
        for (const [lbl, cnt] of Object.entries(counts)) {
            if (cnt > maxAll) {
                maxAll = cnt;
                bestLabel = lbl;
            }
        }
    }
    return bestLabel;
}

function parseCoordsFromLocation(location) {
    const raw = String(location || '').trim();
    if (!raw) return null;
    const pair = raw.match(/(-?\d+\.?\d*)\s*[,;]\s*(-?\d+\.?\d*)/);
    if (pair) {
        const lat = parseFloat(pair[1]);
        const lng = parseFloat(pair[2]);
        if (lat >= 30 && lat <= 38 && lng >= 7 && lng <= 12) {
            return {
                top: 0.08 + ((38 - lat) / 8) * 0.84,
                left: 0.12 + ((lng - 7) / 5) * 0.76,
            };
        }
    }
    const lower = raw.toLowerCase();
    for (const [key, pos] of Object.entries(TN_CITY_POSITIONS)) {
        if (lower.includes(key.replace(/_/g, ' ')) || lower.includes(key)) return { ...pos };
    }
    return null;
}

function mapPositionForLocation(location, index) {
    const parsed = parseCoordsFromLocation(location);
    if (parsed) return parsed;
    const n = index % 8;
    return {
        top: 0.2 + (n % 4) * 0.14,
        left: 0.32 + Math.floor(n / 4) * 0.22,
    };
}

async function loadFleetContext() {
    const [machines, clients] = await Promise.all([
        prisma.machine.findMany({
            orderBy: { updatedAt: 'desc' },
            include: {
                predictions: {
                    orderBy: { createdAt: 'desc' },
                    take: 1
                }
            }
        }),
        prisma.client.findMany({ include: { user: true } }),
    ]);
    const clientById = new Map(clients.map((c) => [c.clientId, c]));
    const enriched = machines.map((m) => {
        const client = m.companyId ? clientById.get(m.companyId) : null;
        const location =
            String(m.location || '').trim() ||
            String(client?.location || '').trim() ||
            String(client?.user?.adresse || '').trim();
        return { ...m, resolvedLocation: location };
    });
    return { machines: enriched, clients };
}

async function getKpis() {
    const [clients, machines, machinesEnLigne, concepteurs, technicians, documents] =
        await Promise.all([
            prisma.client.count(),
            prisma.machine.count(),
            prisma.machine.count({
                where: {
                    status: {
                        in: [
                            ...RUNNING_STATUSES,
                            // lowercase variants often stored via mobile/web forms
                            'running', 'normal', 'Normal', 'online', 'active', 'working',
                            'en travail', 'en marche', 'en service', 'en production',
                            'en fonctionnement', 'en cours', 'opérationnel',
                        ],
                    },
                },
            }),
            prisma.concepteur.count(),
            prisma.technician.count(),
            prisma.document.count(),
        ]);
    return {
        clients,
        machines,
        machinesEnLigne,
        concepteurs,
        technicians,
        documents,
    };
}

async function getFleetOverview() {
    const { machines } = await loadFleetContext();
    const risks = machines.map((m) => riskPctForMachine(m));
    const avgRisk = risks.length
        ? Math.round(risks.reduce((a, b) => a + b, 0) / risks.length)
        : 0;
    const stableCount = machines.filter((m) => riskPctForMachine(m) < 40).length;
    const stablePct = machines.length
        ? Math.round((stableCount / machines.length) * 100)
        : 100;
    const running = machines.filter((m) => isRunning(m.status));
    const markers = running.map((m, i) => ({
        machineId: m.id,
        name: m.name,
        location: m.resolvedLocation,
        status: m.status,
        riskPct: riskPctForMachine(m),
        ...mapPositionForLocation(m.resolvedLocation, i),
    }));

    return {
        riskPct: avgRisk,
        stablePct,
        riskMode: dominantRiskMode(machines),
        machinesTracked: machines.length,
        machinesRunning: running.length,
        markers,
    };
}

module.exports = { getKpis, getFleetOverview };
