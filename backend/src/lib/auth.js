const bcrypt = require('bcryptjs');
const { prisma } = require('./prisma');
const { signToken, JWT_SECRET, jwt } = require('./jwtToken');

async function hashPassword(plain) {
    return bcrypt.hash(String(plain), 10);
}

async function verifyPassword(plain, hash) {
    return bcrypt.compare(String(plain), String(hash));
}

function getAuthUserId(auth) {
    const raw = auth?.sub ?? auth?.id ?? auth?.userId ?? 0;
    const userId = Number(raw);
    return Number.isFinite(userId) && userId > 0 ? userId : 0;
}

function requireAuth(req, res, next) {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) {
        return res.status(401).json({ error: 'Authentification requise' });
    }
    try {
        req.auth = jwt.verify(token, JWT_SECRET);
        return next();
    } catch {
        return res.status(401).json({ error: 'Jeton invalide ou expiré' });
    }
}

function requireFleetManager(req, res, next) {
    const r = String(req.auth?.role || '').toLowerCase();
    if (r === 'superadmin' || r === 'admin' || r === 'conception') return next();
    return res.status(403).json({ error: 'Accès refusé' });
}

/** Réponse JSON login — délégué à la couche View MVC. */
function loginPayload(user, profileExtra = {}) {
    const { loginResponse } = require('../views/userView');
    return loginResponse(user, profileExtra);
}

async function createUserWithProfile(role, userFields, profileData = {}) {
    const { nextBusinessId } = require('./ids');
    const email = String(userFields.email || '').trim().toLowerCase();

    // Vérifier l'existant hors transaction pour éviter les verrous inutiles
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) {
        const err = new Error('Email déjà utilisé');
        err.status = 409;
        throw err;
    }

    const hashedPassword = await hashPassword(userFields.password);

    return prisma.$transaction(async (tx) => {
        const user = await tx.user.create({
            data: {
                email,
                nom: String(userFields.nom || '').trim(),
                adresse: String(userFields.adresse || '').trim(),
                role,
                password: hashedPassword,
            },
        });

        let profile;
        const base = { userId: user.id, ...profileData };

        switch (role) {
            case 'admin':
            case 'superadmin':
                profile = await tx.admin.create({ data: base });
                break;
            case 'client':
                profile = await tx.client.create({
                    data: {
                        ...base,
                        clientId: profileData.clientId || nextBusinessId('CLI'),
                    },
                });
                break;
            case 'conception':
                profile = await tx.concepteur.create({ data: base });
                break;
            case 'technician':
                profile = await tx.technician.create({
                    data: {
                        ...base,
                        technicianId: profileData.technicianId || nextBusinessId('TEC'),
                    },
                });
                break;
            case 'maintenance':
                profile = await tx.maintenanceAgent.create({
                    data: {
                        ...base,
                        maintenanceAgentId:
                            profileData.maintenanceAgentId || nextBusinessId('MNT'),
                    },
                });
                break;
            default:
                throw new Error(`Rôle inconnu: ${role}`);
        }

        return { user, profile };
    });
}

module.exports = {
    hashPassword,
    verifyPassword,
    signToken,
    getAuthUserId,
    requireAuth,
    requireFleetManager,
    loginPayload,
    createUserWithProfile,
    prisma,
};
