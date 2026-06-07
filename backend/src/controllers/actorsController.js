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

async function listConcepteurs(req, res) {
    try {
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
        if (!email || !username || !password) {
            return res.status(400).json({ error: 'Email, nom et mot de passe obligatoires' });
        }
        const { user, profile } = await createUserWithProfile(
            'conception',
            { email, nom: username, password, adresse: location },
            { location },
        );
        createdUserId = user.id;

        // Tentative d'envoi d'email
        const credentialsEmail = await sendWelcomeEmail(email, username, password);

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
        const rows = await ActorModel.listTechnicians();
        return res.json(
            rows.map((p) => mergeUserProfile(p.user, p, { technicianId: p.technicianId })),
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function listMaintenanceAgents(req, res) {
    try {
        const rows = await ActorModel.listMaintenanceAgents();
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

module.exports = {
    listConcepteurs,
    createConcepteur,
    getConcepteur,
    updateConcepteur,
    getMyConcepteurProfile,
    updateMyConcepteurProfile,
    listTechnicians,
    listMaintenanceAgents,
};
