const UserModel = require('../models/userModel');
const { verifyPassword, createUserWithProfile } = require('../lib/auth');
const { mergeUserProfile, loginResponse } = require('../views/userView');
const {
    isGoogleOAuthConfigured,
    buildGoogleOAuthRedirectUri,
    buildAppRedirectUrl,
    DEFAULT_WEB_APP_URL,
    handleGoogleIdToken,
    exchangeCodeForIdToken,
} = require('../lib/googleAuth');
const { validateLogin, validateClientSelfRegister } = require('../lib/validators');

async function login(req, res) {
    try {
        const loginErrors = validateLogin(req.body);
        if (loginErrors.length > 0) {
            return res.status(400).json({ error: loginErrors.join(' | '), errors: loginErrors });
        }
        const user = await UserModel.findByEmail(req.body.email);
        if (!user) {
            return res.status(401).json({ error: 'Email ou mot de passe incorrect' });
        }
        const ok = await verifyPassword(req.body.password, user.password);
        if (!ok) {
            return res.status(401).json({ error: 'Email ou mot de passe incorrect' });
        }
        if (await UserModel.isClientLoginDisabled(user.id)) {
            return res.status(403).json({ error: 'Compte client désactivé' });
        }
        const extras = await UserModel.getProfileExtras(user);
        return res.json(loginResponse(user, extras));
    } catch (err) {
        console.error('POST /login', err);
        return res.status(500).json({ error: err.message });
    }
}

function googleStatus(req, res) {
    res.json({ configured: isGoogleOAuthConfigured() });
}

function googleStart(req, res) {
    try {
        if (!isGoogleOAuthConfigured()) {
            return res.status(503).json({
                error: 'Google OAuth non configuré',
                hint: 'GOOGLE_CLIENT_ID et GOOGLE_CLIENT_SECRET dans backend/.env',
            });
        }
        const returnUrl = String(req.query?.returnUrl || DEFAULT_WEB_APP_URL).trim();
        const state = Buffer.from(
            JSON.stringify({ returnUrl, ts: Date.now() }),
            'utf8',
        ).toString('base64url');
        const redirectUri = buildGoogleOAuthRedirectUri(req);
        const oauthUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
        oauthUrl.searchParams.set('client_id', String(process.env.GOOGLE_CLIENT_ID || '').trim());
        oauthUrl.searchParams.set('redirect_uri', redirectUri);
        oauthUrl.searchParams.set('response_type', 'code');
        oauthUrl.searchParams.set('scope', 'openid email profile');
        oauthUrl.searchParams.set('prompt', 'select_account');
        oauthUrl.searchParams.set('state', state);
        return res.redirect(oauthUrl.toString());
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function googleCallback(req, res) {
    let returnUrl = DEFAULT_WEB_APP_URL;
    try {
        const stateRaw = String(req.query?.state || '').trim();
        if (stateRaw) {
            try {
                const parsed = JSON.parse(Buffer.from(stateRaw, 'base64url').toString('utf8'));
                returnUrl = String(parsed?.returnUrl || returnUrl).trim() || returnUrl;
            } catch {
                /* ignore */
            }
        }
        const code = String(req.query?.code || '').trim();
        if (!code) {
            return res.redirect(
                buildAppRedirectUrl(returnUrl, { googleAuth: '0', error: 'Code Google absent' }),
            );
        }
        if (!isGoogleOAuthConfigured()) {
            return res.redirect(
                buildAppRedirectUrl(returnUrl, {
                    googleAuth: '0',
                    error: 'GOOGLE_CLIENT_ID ou GOOGLE_CLIENT_SECRET manquant',
                }),
            );
        }
        const redirectUri = buildGoogleOAuthRedirectUri(req);
        const idToken = await exchangeCodeForIdToken(code, redirectUri);
        const location = String(req.query?.location || '').trim();
        const result = await handleGoogleIdToken(idToken, location);
        return res.redirect(buildAppRedirectUrl(returnUrl, result.redirect));
    } catch (err) {
        console.error('[Google OAuth callback]', err.message);
        return res.redirect(
            buildAppRedirectUrl(returnUrl, {
                googleAuth: '0',
                error: err.message || 'Callback Google impossible',
            }),
        );
    }
}

async function clientGoogleAuth(req, res) {
    try {
        const idToken = String(req.body?.idToken || '').trim();
        const location = String(req.body?.location || '').trim();
        if (!idToken) {
            return res.status(400).json({ error: 'idToken Google requis' });
        }
        if (!isGoogleOAuthConfigured()) {
            return res.status(503).json({ error: 'Google OAuth non configuré' });
        }
        const result = await handleGoogleIdToken(idToken, location);
        return res.status(result.status).json(result.body);
    } catch (err) {
        const status = err.status || 401;
        return res.status(status).json({ error: err.message || 'Échec auth Google' });
    }
}

async function clientSelfRegister(req, res) {
    try {
        const email = String(req.body.email || '').trim().toLowerCase();
        const nom = String(req.body.name || req.body.nom || '').trim();
        const password = String(req.body.password || '');
        const location = String(req.body.location || req.body.address || req.body.adresse || '').trim();
        const registerErrors = validateClientSelfRegister(req.body);
        if (registerErrors.length > 0) {
            return res.status(400).json({ error: registerErrors.join(' | '), errors: registerErrors });
        }
        const { user, profile } = await createUserWithProfile(
            'client',
            { email, nom, password, adresse: location },
            { location, motorType: String(req.body.motorType || 'Général') },
        );
        const body = mergeUserProfile(user, profile);
        return res.status(201).json({
            ...body,
            ...loginResponse(user, { clientId: profile.clientId, companyId: profile.clientId }),
        });
    } catch (err) {
        const status = err.status || 500;
        return res.status(status).json({ error: err.message });
    }
}

async function maintenanceLogin(req, res) {
    try {
        const user = await UserModel.findByEmail(req.body.email);
        if (!user || user.role !== 'maintenance') {
            return res.status(401).json({ error: 'Compte maintenance introuvable' });
        }
        const ok = await verifyPassword(req.body.password, user.password);
        if (!ok) {
            return res.status(401).json({ error: 'Email ou mot de passe incorrect' });
        }
        const agent = await UserModel.findMaintenanceAgent(user.id);
        return res.json(
            loginResponse(user, {
                maintenanceAgentId: agent?.maintenanceAgentId,
                clientId: agent?.clientId,
            }),
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = {
    login,
    googleStatus,
    googleStart,
    googleCallback,
    clientGoogleAuth,
    clientSelfRegister,
    maintenanceLogin,
};
