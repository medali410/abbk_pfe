const crypto = require('crypto');
const { OAuth2Client } = require('google-auth-library');
const { prisma } = require('./prisma');
const { loginPayload, createUserWithProfile } = require('./auth');
const { mergeUserProfile, parseJsonArray } = require('./serialize');
const { nextBusinessId } = require('./ids');

const DEFAULT_WEB_APP_URL = String(process.env.APP_WEB_URL || 'http://localhost:50924').trim();

function googleClientId() {
    return String(process.env.GOOGLE_CLIENT_ID || '').trim();
}

function googleClientSecret() {
    return String(process.env.GOOGLE_CLIENT_SECRET || '').trim();
}

function getGoogleOAuthClient() {
    const id = googleClientId();
    return new OAuth2Client(id || undefined);
}

function isGoogleOAuthConfigured() {
    const id = googleClientId();
    const secret = googleClientSecret();
    if (!id || !secret) return false;
    if (/xxx|your_|changez|example|placeholder/i.test(id + secret)) return false;
    return id.length > 12 && secret.length > 8;
}

function buildGoogleOAuthRedirectUri(req) {
    const envUri = String(process.env.GOOGLE_REDIRECT_URI || '').trim();
    if (envUri) return envUri;
    return `${req.protocol}://${req.get('host')}/api/auth/google/callback`;
}

function buildAppRedirectUrl(rawReturnUrl, params) {
    const safeBase = String(rawReturnUrl || DEFAULT_WEB_APP_URL).trim() || DEFAULT_WEB_APP_URL;
    const hashIndex = safeBase.indexOf('#');
    if (hashIndex >= 0) {
        const beforeHash = safeBase.slice(0, hashIndex);
        const hashPart = safeBase.slice(hashIndex + 1);
        const [hashPath, hashQuery = ''] = hashPart.split('?');
        const hashParams = new URLSearchParams(hashQuery);
        for (const [k, v] of Object.entries(params)) {
            hashParams.set(k, String(v ?? ''));
        }
        return `${beforeHash}#${hashPath}?${hashParams.toString()}`;
    }
    const joiner = safeBase.includes('?') ? '&' : '?';
    const qp = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) {
        qp.set(k, String(v ?? ''));
    }
    return `${safeBase}${joiner}${qp.toString()}`;
}

function generateProvisionPassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let out = '';
    for (let i = 0; i < 14; i += 1) out += chars[crypto.randomInt(0, chars.length)];
    return out;
}

async function verifyGoogleIdToken(idToken) {
    const clientId = googleClientId();
    const ticket = await getGoogleOAuthClient().verifyIdToken({
        idToken,
        ...(clientId ? { audience: clientId } : {}),
    });
    const payload = ticket.getPayload();
    if (!payload) throw new Error('Token Google invalide');
    const email = String(payload.email || '').trim().toLowerCase();
    const emailVerified = Boolean(payload.email_verified);
    const name = String(payload.name || 'Client Google').trim();
    if (!email.includes('@')) throw new Error('Email Google invalide');
    if (!emailVerified) throw new Error('Email Google non vérifié');
    return { email, name, googleSub: String(payload.sub || '').trim() };
}

async function exchangeCodeForIdToken(code, redirectUri) {
    const body = new URLSearchParams({
        code,
        client_id: googleClientId(),
        client_secret: googleClientSecret(),
        redirect_uri: redirectUri,
        grant_type: 'authorization_code',
    });
    const resp = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
    });
    const data = await resp.json();
    if (!resp.ok) {
        const msg = data?.error_description || data?.error || resp.statusText;
        throw new Error(msg);
    }
    const idToken = String(data.id_token || '').trim();
    if (!idToken) throw new Error('ID token Google absent');
    return idToken;
}

function technicianRedirectParams(user, tech, token) {
    const machineIds = parseJsonArray(tech.machineIds);
    return {
        googleAuth: '1',
        token,
        role: 'technician',
        technicianId: String(tech.technicianId || ''),
        id: String(tech.technicianId || ''),
        _id: String(user.id),
        name: String(user.nom || ''),
        email: String(user.email || ''),
        companyId: String(tech.companyId || ''),
        machineIds: machineIds.map((x) => String(x)).join(','),
        specialization: String(tech.specialization || ''),
        status: String(tech.status || ''),
    };
}

function clientRedirectParams(user, client, token) {
    return {
        googleAuth: '1',
        token,
        role: 'client',
        clientId: String(client.clientId || ''),
        name: String(user.nom || ''),
        email: String(user.email || ''),
        location: String(client.location || user.adresse || ''),
    };
}

async function resolveGoogleLogin({ email, name, location = '' }) {
    const user = await prisma.user.findUnique({ where: { email } });
    const loc = String(location || '').trim();

    if (user) {
        const role = String(user.role || '').toLowerCase();
        if (role === 'admin' || role === 'superadmin') {
            const err = new Error(
                'Compte administrateur : utilisez la connexion par email et mot de passe.',
            );
            err.status = 403;
            throw err;
        }
        if (role === 'conception') {
            const p = await prisma.concepteur.findUnique({ where: { userId: user.id } });
            const token = loginPayload(user, { companyId: p?.companyId }).token;
            return {
                status: 200,
                body: {
                    ...mergeUserProfile(user, p),
                    ...loginPayload(user, { companyId: p?.companyId }),
                },
                redirect: {
                    googleAuth: '1',
                    token,
                    role: 'conception',
                    id: String(user.id),
                    email: user.email,
                    name: user.nom,
                    companyId: String(p?.companyId || ''),
                },
            };
        }
        if (role === 'maintenance') {
            const p = await prisma.maintenanceAgent.findUnique({ where: { userId: user.id } });
            const extras = {
                maintenanceAgentId: p?.maintenanceAgentId,
                clientId: p?.clientId,
            };
            const token = loginPayload(user, extras).token;
            return {
                status: 200,
                body: { ...mergeUserProfile(user, p), ...loginPayload(user, extras) },
                redirect: { googleAuth: '1', token, role: 'maintenance' },
            };
        }
        if (role === 'technician') {
            const p = await prisma.technician.findUnique({ where: { userId: user.id } });
            const extras = {
                technicianId: p?.technicianId,
                companyId: p?.companyId,
            };
            const token = loginPayload(user, extras).token;
            return {
                status: 200,
                body: { ...mergeUserProfile(user, p), ...loginPayload(user, extras) },
                redirect: technicianRedirectParams(user, p, token),
            };
        }
        if (role === 'client') {
            const p = await prisma.client.findUnique({ where: { userId: user.id } });
            if (p?.loginDisabled) {
                const err = new Error('Compte client désactivé');
                err.status = 403;
                throw err;
            }
            if (loc && !String(p?.location || '').trim()) {
                await prisma.client.update({
                    where: { id: p.id },
                    data: { location: loc },
                });
                if (!String(user.adresse || '').trim()) {
                    await prisma.user.update({
                        where: { id: user.id },
                        data: { adresse: loc },
                    });
                }
            }
            const refreshed = await prisma.client.findUnique({ where: { userId: user.id } });
            const extras = { clientId: refreshed.clientId, companyId: refreshed.clientId };
            const token = loginPayload(user, extras).token;
            return {
                status: 200,
                body: { ...mergeUserProfile(user, refreshed), ...loginPayload(user, extras) },
                redirect: clientRedirectParams(user, refreshed, token),
            };
        }
    }

    const { user: newUser, profile } = await createUserWithProfile(
        'client',
        {
            email,
            nom: name,
            password: generateProvisionPassword(),
            adresse: loc || 'Inconnu',
        },
        {
            clientId: nextBusinessId('CLI'),
            location: loc || 'Inconnu',
            motorType: 'ac-induction',
        },
    );
    const extras = { clientId: profile.clientId, companyId: profile.clientId };
    const token = loginPayload(newUser, extras).token;
    return {
        status: 201,
        body: { ...mergeUserProfile(newUser, profile), ...loginPayload(newUser, extras) },
        redirect: clientRedirectParams(newUser, profile, token),
    };
}

async function handleGoogleIdToken(idToken, location = '') {
    const { email, name } = await verifyGoogleIdToken(idToken);
    return resolveGoogleLogin({ email, name, location });
}

module.exports = {
    isGoogleOAuthConfigured,
    buildGoogleOAuthRedirectUri,
    buildAppRedirectUrl,
    DEFAULT_WEB_APP_URL,
    verifyGoogleIdToken,
    exchangeCodeForIdToken,
    handleGoogleIdToken,
    resolveGoogleLogin,
};
