const { prisma } = require('../lib/prisma');
const { mergeUserProfile, parseJsonArray } = require('../views/userView');
const { serializeMachine } = require('../views/machineView');

function actorName(user, fallback = 'Utilisateur') {
    return (user?.nom || fallback).trim() || fallback;
}

async function findPurchasedMachines(concepteur) {
    const concepteurIdStr = String(concepteur.id);
    const ownedMachineIds = parseJsonArray(concepteur.machineIds)
        .map((id) => String(id).trim())
        .filter(Boolean);

    const orFilters = [{ concepteurId: concepteurIdStr }];
    if (ownedMachineIds.length > 0) {
        orFilters.push({ id: { in: ownedMachineIds } });
    }

    return prisma.machine.findMany({
        where: {
            companyId: { not: '' },
            OR: orFilters,
        },
        orderBy: { updatedAt: 'desc' },
    });
}

async function buildProjectTeam(concepteur) {
    const machines = await findPurchasedMachines(concepteur);

    const linkedCompanyIds = [
        ...new Set(
            machines
                .map((machine) => String(machine.companyId || '').trim())
                .filter(Boolean),
        ),
    ];

    const [allClients, allTechnicians, allMaintenanceAgents, allConcepteurs] =
        await Promise.all([
            linkedCompanyIds.length > 0
                ? prisma.client.findMany({
                      where: { clientId: { in: linkedCompanyIds } },
                      include: { user: true },
                      orderBy: { id: 'desc' },
                  })
                : Promise.resolve([]),
            prisma.technician.findMany({ include: { user: true } }),
            prisma.maintenanceAgent.findMany({ include: { user: true } }),
            prisma.concepteur.findMany({ include: { user: true } }),
        ]);

    const technicians = allTechnicians.map((row) =>
        mergeUserProfile(row.user, row, { technicianId: row.technicianId }),
    );
    const maintenanceAgents = allMaintenanceAgents.map((row) =>
        mergeUserProfile(row.user, row, {
            maintenanceAgentId: row.maintenanceAgentId,
            firstName: row.firstName,
            lastName: row.lastName,
            name: `${row.firstName} ${row.lastName}`.trim() || row.user.nom,
        }),
    );
    const concepteurs = allConcepteurs.map((row) =>
        mergeUserProfile(row.user, row, { concepteurId: row.id }),
    );

    const clients = [];
    for (const clientRow of allClients) {
        const clientProfile = mergeUserProfile(clientRow.user, clientRow);
        const clientId = clientRow.clientId;
        const clientKeys = new Set(
            [clientId, String(clientRow.id), String(clientRow.userId)]
                .map((v) => String(v || '').trim())
                .filter(Boolean),
        );

        const matchesKey = (value) => {
            const normalized = String(value || '').trim();
            if (!normalized) return false;
            for (const key of clientKeys) {
                if (key === normalized) return true;
            }
            return false;
        };

        const clientTechnicians = technicians.filter((t) =>
            matchesKey(t.companyId),
        );
        const clientMaintenanceAgents = maintenanceAgents.filter((a) =>
            matchesKey(a.clientId),
        );
        const clientConcepteurs = concepteurs.filter((c) =>
            matchesKey(c.companyId || c.clientId),
        );
        const clientMachines = machines
            .filter((m) => matchesKey(m.companyId))
            .map(serializeMachine);

        clients.push({
            ...clientProfile,
            clientId,
            name: actorName(clientRow.user, clientId),
            techniciansCount: clientTechnicians.length,
            maintenanceCount: clientMaintenanceAgents.length,
            concepteursCount: clientConcepteurs.length,
            machinesCount: clientMachines.length,
            machines: clientMachines,
            technicians: clientTechnicians,
            maintenanceAgents: clientMaintenanceAgents,
            concepteurs: clientConcepteurs,
        });
    }

    return {
        clients,
        technicians,
        maintenanceAgents,
        concepteurs,
    };
}

async function getConcepteurProfileDashboard(userId) {
    let row = await prisma.concepteur.findFirst({
        where: { userId },
        include: { user: true },
    });

    if (!row) {
        const user = await prisma.user.findFirst({
            where: { id: userId, role: 'conception' },
        });
        if (user) {
            const profile = await prisma.concepteur.create({ data: { userId } });
            row = { ...profile, user };
        }
    }

    if (!row) return null;

    const projectTeam = await buildProjectTeam(row);
    return { row, projectTeam };
}

function buildConcepteurProfileUpdate(body = {}) {
    const userData = {};
    const profileData = {};

    const username = body.username ?? body.name ?? body.nom ?? body.displayName;
    const email = body.email ?? body.mail;
    const password = body.password;
    const address = body.address ?? body.adresse ?? body.street;

    if (username !== undefined && String(username).trim()) {
        userData.nom = String(username).trim();
    }
    if (email !== undefined && String(email).trim()) {
        userData.email = String(email).trim().toLowerCase();
    }
    if (address !== undefined) {
        userData.adresse = String(address).trim();
        profileData.location = String(address).trim();
    }
    if (body.location !== undefined) {
        profileData.location = String(body.location).trim();
    }

    const profileFields = {
        imageUrl: body.imageUrl ?? body.photoUrl ?? body.avatarUrl,
        phone: body.phone ?? body.telephone ?? body.mobile ?? body.phoneNumber,
        city: body.city ?? body.ville,
        country: body.country ?? body.pays,
        websiteUrl: body.websiteUrl ?? body.siteWeb ?? body.website ?? body.url,
        profileUrl: body.profileUrl ?? body.linkedinUrl ?? body.portfolioUrl,
        status: body.status ?? body.statut,
        specialite:
            body.specialite ??
            body.speciality ??
            body.specialty ??
            body.poste ??
            body.title ??
            body.jobTitle,
        companyId: body.companyId ?? body.companyName ?? body.company ?? body.organization,
    };

    for (const [key, value] of Object.entries(profileFields)) {
        if (value !== undefined) {
            profileData[key] = String(value).trim();
        }
    }

    return { userData, profileData, password };
}

module.exports = {
    buildProjectTeam,
    getConcepteurProfileDashboard,
    buildConcepteurProfileUpdate,
};
