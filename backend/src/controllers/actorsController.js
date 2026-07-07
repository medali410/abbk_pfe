const ActorModel = require('../models/actorModel');
const {
    getConcepteurProfileDashboard,
    buildConcepteurProfileUpdate,
} = require('../models/concepteurProfileModel');
const { mergeUserProfile } = require('../views/userView');
const { serializeConcepteurProfileDashboard } = require('../views/concepteurProfileView');
const { createUserWithProfile, hashPassword, getAuthUserId } = require('../lib/auth');
const { sendWelcomeEmail } = require('../lib/emailService');
const { prisma } = require('../lib/prisma');
const { validateConcepteurProfileUpdate, validateCreateConcepteur } = require('../lib/validators');

async function listConcepteurs(req, res) {
    try {
        const role = req.auth?.role;
        if (role === 'conception' || role === 'concepteur') {
            const userId = getAuthUserId(req.auth);
            const concepteur = await prisma.concepteur.findUnique({ where: { userId }, include: { user: true } });
            if (!concepteur) return res.json([]);
            return res.json([mergeUserProfile(concepteur.user, concepteur, { concepteurId: concepteur.id })]);
        }
        const rows = await ActorModel.listConcepteurs();
        res.set('Cache-Control', 'no-store');
        return res.json(
            rows.map((p) => mergeUserProfile(p.user, p, { concepteurId: p.id })),
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function createConcepteur(req, res) {
    let createdUserId = null;
    try {
        const { email, username, password, location } = req.body;
        const validationErrors = validateCreateConcepteur(req.body);
        if (validationErrors.length > 0) {
            return res.status(400).json({ error: validationErrors.join(' | '), errors: validationErrors });
        }
        const { user, profile } = await createUserWithProfile(
            'conception',
            { email, nom: username, password, adresse: location },
            { location },
        );
        createdUserId = user.id;

        // Tentative d'envoi d'email
        let credentialsEmail;
        if (req.body.sendEmail !== false) {
            credentialsEmail = await sendWelcomeEmail(email, username, password);

            // Si l'envoi échoue, on annule la création du compte (demande utilisateur)
            if (!credentialsEmail.sent) {
                await prisma.user.delete({ where: { id: createdUserId } });
                createdUserId = null;

                const errorMsg =
                    credentialsEmail.reason === 'smtp_credentials_missing'
                        ? 'Configuration SMTP manquante dans le fichier .env (SMTP_USER/SMTP_PASS)'
                        : `Échec de l'envoi de l'email : ${credentialsEmail.detail || 'Erreur inconnue'}`;

                return res.status(500).json({
                    error: errorMsg,
                    hint: "Le compte n'a pas été créé car l'email n'a pu être envoyé.",
                });
            }
        } else {
            credentialsEmail = { sent: false, reason: 'skipped_by_user' };
        }

        return res.status(201).json({
            ...mergeUserProfile(user, profile, { concepteurId: profile.id }),
            credentialsEmail,
        });
    } catch (err) {
        if (createdUserId) {
            try {
                await prisma.user.delete({ where: { id: createdUserId } });
            } catch (e) {
                /* ignore */
            }
        }
        return res.status(err.status || 500).json({ error: err.message });
    }
}

async function getConcepteur(req, res) {
    try {
        const { id } = req.params;
        const convid = parseInt(id, 10) || 0;

        const role = req.auth?.role;
        if (role === 'conception' || role === 'concepteur') {
            const userId = getAuthUserId(req.auth);
            const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
            if (!concepteur || (concepteur.id !== convid && concepteur.userId !== convid)) {
                return res.status(403).json({ error: 'Vous ne pouvez accéder qu\'à votre propre compte.' });
            }
        }

        let row = await prisma.concepteur.findFirst({
            where: {
                OR: [{ id: convid }, { userId: convid }],
            },
            include: { user: true },
        });

        // AUTO-RÉPARATION : Si l'utilisateur existe mais pas le profil concepteur
        if (!row) {
            const user = await prisma.user.findFirst({
                where: { id: convid, role: 'conception' },
            });
            if (user) {
                const profile = await prisma.concepteur.create({
                    data: { userId: user.id },
                });
                row = { ...profile, user };
            }
        }

        if (!row) return res.status(404).json({ error: 'Concepteur introuvable' });
        return res.json(mergeUserProfile(row.user, row, { concepteurId: row.id }));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function updateConcepteur(req, res) {
    try {
        const { id } = req.params;
        const { email, username, password, location } = req.body;

        const convid = parseInt(id, 10) || 0;

        const role = req.auth?.role;
        if (role === 'conception' || role === 'concepteur') {
            const userId = getAuthUserId(req.auth);
            const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
            if (!concepteur || (concepteur.id !== convid && concepteur.userId !== convid)) {
                return res.status(403).json({ error: 'Vous ne pouvez modifier que votre propre compte.' });
            }
        }

        let existing = await prisma.concepteur.findFirst({
            where: {
                OR: [{ id: convid }, { userId: convid }],
            },
            include: { user: true },
        });

        // AUTO-RÉPARATION : Créer le profil s'il manque
        if (!existing) {
            const user = await prisma.user.findFirst({
                where: { id: convid, role: 'conception' },
            });
            if (user) {
                const profile = await prisma.concepteur.create({
                    data: { userId: user.id },
                });
                existing = { ...profile, user };
            }
        }

        if (!existing) return res.status(404).json({ error: 'Concepteur introuvable' });

        const userData = {};
        if (email) userData.email = email;
        if (username) userData.nom = username;
        if (password) {
            userData.password = await hashPassword(password);
        }
        if (location) userData.adresse = location;

        const updatedUser = await prisma.user.update({
            where: { id: existing.userId },
            data: userData,
        });

        const updatedProfile = await prisma.concepteur.update({
            where: { id: existing.id },
            data: { location: location || existing.location },
        });

        return res.json(
            mergeUserProfile(updatedUser, updatedProfile, {
                concepteurId: updatedProfile.id,
            }),
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function listTechnicians(req, res) {
    try {
        let rows = await ActorModel.listTechnicians();

        const role = req.auth?.role;
        if (role === 'conception' || role === 'concepteur') {
            const userId = getAuthUserId(req.auth);
            const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
            if (concepteur) {
                const userConcepteurId = String(concepteur.id);
                let allowedIds = [];
                try { allowedIds = JSON.parse(concepteur.machineIds || '[]'); } catch (e) { }
                const machines = await prisma.machine.findMany({
                    where: {
                        OR: [
                            { concepteurId: userConcepteurId },
                            { id: { in: allowedIds } }
                        ]
                    }
                });
                const machineIdsStr = machines.map(m => String(m.id));
                const companyIds = [...new Set(machines.map(m => m.companyId).filter(Boolean))];
                rows = rows.filter(t => {
                    if (t.companyId && companyIds.includes(t.companyId)) return true;
                    let tMachineIds = [];
                    try { tMachineIds = JSON.parse(t.machineIds || '[]'); } catch (e) { }
                    return tMachineIds.some(mId => machineIdsStr.includes(String(mId)));
                });
            } else {
                rows = [];
            }
        }

        return res.json(
            rows.map((p) => mergeUserProfile(p.user, p, {
                technicianId: p.technicianId,
                firstName: p.firstName,
                lastName: p.lastName,
                name: `${p.firstName} ${p.lastName}`.trim() || p.user.nom,
            })),
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function createTechnician(req, res) {
    let createdUserId = null;
    try {
        const { email, password, name, firstName, lastName, address, location, companyId, machineIds, specialization, status } = req.body;

        const { user, profile } = await createUserWithProfile(
            'technician',
            { email, nom: name, password, adresse: address || location },
            {
                firstName: firstName || '',
                lastName: lastName || '',
                companyId: companyId || '',
                specialization: specialization || 'Vibration',
                status: status || 'Disponible',
                machineIds: Array.isArray(machineIds) ? JSON.stringify(machineIds) : '[]'
            }
        );
        createdUserId = user.id;

        let credentialsEmail;
        if (req.body.sendEmail !== false) {
            credentialsEmail = await sendWelcomeEmail(email, `${firstName || ''} ${lastName || ''}`.trim() || name || user.nom, password, 'Technicien');
        } else {
            credentialsEmail = { sent: false, reason: 'skipped_by_user' };
        }

        return res.status(201).json({
            ...mergeUserProfile(user, profile, {
                technicianId: profile.technicianId,
                firstName: profile.firstName,
                lastName: profile.lastName,
                name: `${profile.firstName} ${profile.lastName}`.trim() || user.nom,
            }),
            credentialsEmail
        });
    } catch (err) {
        if (createdUserId) {
            try {
                await prisma.user.delete({ where: { id: createdUserId } });
            } catch (e) { }
        }
        return res.status(err.status || 500).json({ error: err.message });
    }
}

async function updateTechnician(req, res) {
    try {
        const { id } = req.params;
        const { email, password, name, firstName, lastName, address, location, companyId, machineIds, specialization, status } = req.body;

        const tid = parseInt(id, 10) || 0;
        let existing = await prisma.technician.findFirst({
            where: {
                OR: [{ id: tid }, { technicianId: id }]
            },
            include: { user: true }
        });

        if (!existing) return res.status(404).json({ error: 'Technicien introuvable' });

        const userData = {};
        if (email) userData.email = email;
        if (name) userData.nom = name;
        if (password) userData.password = await hashPassword(password);
        if (address || location) userData.adresse = address || location;

        const updatedUser = Object.keys(userData).length > 0
            ? await prisma.user.update({ where: { id: existing.userId }, data: userData })
            : existing.user;

        const profileData = {};
        if (firstName !== undefined) profileData.firstName = firstName;
        if (lastName !== undefined) profileData.lastName = lastName;
        if (companyId !== undefined) profileData.companyId = companyId;
        if (specialization !== undefined) profileData.specialization = specialization;
        if (status !== undefined) profileData.status = status;
        if (machineIds !== undefined) profileData.machineIds = Array.isArray(machineIds) ? JSON.stringify(machineIds) : '[]';

        const updatedProfile = Object.keys(profileData).length > 0
            ? await prisma.technician.update({ where: { id: existing.id }, data: profileData })
            : existing;

        return res.json(
            mergeUserProfile(updatedUser, updatedProfile, {
                technicianId: updatedProfile.technicianId,
                firstName: updatedProfile.firstName,
                lastName: updatedProfile.lastName,
                name: `${updatedProfile.firstName} ${updatedProfile.lastName}`.trim() || updatedUser.nom,
            })
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function listMaintenanceAgents(req, res) {
    try {
        let rows = await ActorModel.listMaintenanceAgents();

        const role = req.auth?.role;
        if (role === 'conception' || role === 'concepteur') {
            const userId = getAuthUserId(req.auth);
            const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
            if (concepteur) {
                const userConcepteurId = String(concepteur.id);
                let allowedIds = [];
                try { allowedIds = JSON.parse(concepteur.machineIds || '[]'); } catch (e) { }
                const machines = await prisma.machine.findMany({
                    where: {
                        OR: [
                            { concepteurId: userConcepteurId },
                            { id: { in: allowedIds } }
                        ]
                    }
                });
                const machineIdsStr = machines.map(m => String(m.id));
                const companyIds = [...new Set(machines.map(m => m.companyId).filter(Boolean))];
                rows = rows.filter(a => {
                    if (a.clientId && companyIds.includes(a.clientId)) return true;
                    let aMachineIds = [];
                    try { aMachineIds = JSON.parse(a.machineIds || '[]'); } catch (e) { }
                    return aMachineIds.some(mId => machineIdsStr.includes(String(mId)));
                });
            } else {
                rows = [];
            }
        }

        return res.json(
            rows.map((a) =>
                mergeUserProfile(a.user, a, {
                    maintenanceAgentId: a.maintenanceAgentId,
                    firstName: a.firstName,
                    lastName: a.lastName,
                    name: `${a.firstName} ${a.lastName}`.trim(),
                }),
            ),
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getMyConcepteurProfile(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const dashboard = await getConcepteurProfileDashboard(userId);
        if (!dashboard) {
            return res.status(404).json({ error: 'Profil concepteur introuvable' });
        }

        res.set('Cache-Control', 'no-store');
        return res.json(
            serializeConcepteurProfileDashboard(
                dashboard.row.user,
                dashboard.row,
                dashboard.projectTeam,
            ),
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function updateMyConcepteurProfile(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const dashboard = await getConcepteurProfileDashboard(userId);
        if (!dashboard) {
            return res.status(404).json({ error: 'Profil concepteur introuvable' });
        }

        const validationErrors = validateConcepteurProfileUpdate(req.body);
        if (validationErrors.length > 0) {
            return res.status(400).json({ error: validationErrors.join(' | '), errors: validationErrors });
        }

        const { userData, profileData, password } = buildConcepteurProfileUpdate(req.body);
        if (password) {
            userData.password = await hashPassword(password);
        }

        const hasUserUpdate = Object.keys(userData).length > 0;
        const hasProfileUpdate = Object.keys(profileData).length > 0;

        const updatedUser = hasUserUpdate
            ? await prisma.user.update({ where: { id: userId }, data: userData })
            : dashboard.row.user;

        const updatedProfile = hasProfileUpdate
            ? await prisma.concepteur.update({
                where: { id: dashboard.row.id },
                data: profileData,
            })
            : dashboard.row;

        const refreshed = await getConcepteurProfileDashboard(userId);
        return res.json(
            serializeConcepteurProfileDashboard(
                refreshed.row.user,
                refreshed.row,
                refreshed.projectTeam,
            ),
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function createMaintenanceAgent(req, res) {
    let createdUserId = null;
    try {
        const { email, password, name, firstName, lastName, address, location, clientId, machineIds } = req.body;

        const { user, profile } = await createUserWithProfile(
            'maintenance',
            { email, nom: name, password, adresse: address || location },
            {
                firstName: firstName || '',
                lastName: lastName || '',
                clientId: clientId || '',
                machineIds: Array.isArray(machineIds) ? JSON.stringify(machineIds) : '[]'
            }
        );
        createdUserId = user.id;

        let credentialsEmail;
        if (req.body.sendEmail !== false) {
            credentialsEmail = await sendWelcomeEmail(email, `${firstName || ''} ${lastName || ''}`.trim() || name || user.nom, password, 'Agent de Maintenance');
        } else {
            credentialsEmail = { sent: false, reason: 'skipped_by_user' };
        }

        return res.status(201).json({
            ...mergeUserProfile(user, profile, {
                maintenanceAgentId: profile.maintenanceAgentId,
                firstName: profile.firstName,
                lastName: profile.lastName,
                name: `${profile.firstName} ${profile.lastName}`.trim(),
            }),
            credentialsEmail
        });
    } catch (err) {
        if (createdUserId) {
            try {
                await prisma.user.delete({ where: { id: createdUserId } });
            } catch (e) { }
        }
        return res.status(err.status || 500).json({ error: err.message });
    }
}

async function updateMaintenanceAgent(req, res) {
    try {
        const { id } = req.params;
        const { email, password, name, firstName, lastName, address, location, clientId, machineIds } = req.body;

        const mntId = parseInt(id, 10) || 0;
        let existing = await prisma.maintenanceAgent.findFirst({
            where: {
                OR: [{ id: mntId }, { maintenanceAgentId: id }]
            },
            include: { user: true }
        });

        if (!existing) return res.status(404).json({ error: 'Maintenance agent introuvable' });

        const userData = {};
        if (email) userData.email = email;
        if (name) userData.nom = name;
        if (password) userData.password = await hashPassword(password);
        if (address || location) userData.adresse = address || location;

        const updatedUser = Object.keys(userData).length > 0
            ? await prisma.user.update({ where: { id: existing.userId }, data: userData })
            : existing.user;

        const profileData = {};
        if (firstName !== undefined) profileData.firstName = firstName;
        if (lastName !== undefined) profileData.lastName = lastName;
        if (clientId !== undefined) profileData.clientId = clientId;
        if (machineIds !== undefined) profileData.machineIds = Array.isArray(machineIds) ? JSON.stringify(machineIds) : '[]';

        const updatedProfile = Object.keys(profileData).length > 0
            ? await prisma.maintenanceAgent.update({ where: { id: existing.id }, data: profileData })
            : existing;

        return res.json(
            mergeUserProfile(updatedUser, updatedProfile, {
                maintenanceAgentId: updatedProfile.maintenanceAgentId,
                firstName: updatedProfile.firstName,
                lastName: updatedProfile.lastName,
                name: `${updatedProfile.firstName} ${updatedProfile.lastName}`.trim(),
            })
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = {
    listConcepteurs,
    createConcepteur,
    getConcepteur,
    updateConcepteur,
    getMyConcepteurProfile,
    updateMyConcepteurProfile,
    listTechnicians,
    createTechnician,
    updateTechnician,
    listMaintenanceAgents,
    createMaintenanceAgent,
    updateMaintenanceAgent,
};
