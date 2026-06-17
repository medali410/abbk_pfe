/**
 * validators.js — Validation centralisée des entrées backend.
 * Toutes les fonctions retournent un objet { valid: bool, error?: string }
 * ou lancent des erreurs HTTP via createValidationError().
 */

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const PHONE_REGEX = /^[+]?[\d\s\-().]{6,20}$/;
const URL_REGEX = /^https?:\/\/.+/i;

/**
 * Crée une erreur avec code HTTP pour les réponses 400.
 */
function createValidationError(message, field = null) {
    const err = new Error(message);
    err.status = 400;
    if (field) err.field = field;
    return err;
}

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

function validateEmail(value, required = true) {
    const v = String(value || '').trim().toLowerCase();
    if (!v) {
        if (required) return { valid: false, error: 'Email obligatoire' };
        return { valid: true };
    }
    if (!EMAIL_REGEX.test(v)) return { valid: false, error: 'Email invalide (ex: nom@domaine.fr)' };
    return { valid: true, value: v };
}

function validatePhone(value, required = false) {
    const v = String(value || '').trim();
    if (!v) {
        if (required) return { valid: false, error: 'Téléphone obligatoire' };
        return { valid: true, value: v };
    }
    if (!PHONE_REGEX.test(v)) return { valid: false, error: 'Téléphone invalide (ex: +216 20 000 000)' };
    return { valid: true, value: v };
}

function validateUrl(value, required = false, label = 'URL') {
    const v = String(value || '').trim();
    if (!v) {
        if (required) return { valid: false, error: `${label} obligatoire` };
        return { valid: true, value: v };
    }
    if (!URL_REGEX.test(v)) return { valid: false, error: `${label} invalide — doit commencer par http:// ou https://` };
    return { valid: true, value: v };
}

function validateNom(value, required = true, label = 'Nom') {
    const v = String(value || '').trim();
    if (!v) {
        if (required) return { valid: false, error: `${label} obligatoire` };
        return { valid: true, value: v };
    }
    if (v.length < 2) return { valid: false, error: `${label} trop court (min 2 caractères)` };
    if (v.length > 100) return { valid: false, error: `${label} trop long (max 100 caractères)` };
    return { valid: true, value: v };
}

function validatePassword(value, required = false) {
    const v = String(value || '');
    if (!v) {
        if (required) return { valid: false, error: 'Mot de passe obligatoire' };
        return { valid: true };
    }
    if (v.length < 6) return { valid: false, error: 'Mot de passe trop court (min 6 caractères)' };
    if (v.length > 128) return { valid: false, error: 'Mot de passe trop long' };
    return { valid: true, value: v };
}

function validateText(value, { required = false, min = 0, max = 255, label = 'Champ' } = {}) {
    const v = String(value || '').trim();
    if (!v) {
        if (required) return { valid: false, error: `${label} obligatoire` };
        return { valid: true, value: v };
    }
    if (min > 0 && v.length < min) return { valid: false, error: `${label} trop court (min ${min} caractères)` };
    if (v.length > max) return { valid: false, error: `${label} trop long (max ${max} caractères)` };
    return { valid: true, value: v };
}

// ---------------------------------------------------------------------------
// Compound validators
// ---------------------------------------------------------------------------

/**
 * Valide le corps d'une mise à jour de profil Concepteur (PATCH /api/concepteurs/me).
 * Retourne { errors: string[] } — tableau vide si tout est valide.
 */
function validateConcepteurProfileUpdate(body = {}) {
    const errors = [];

    // Nom affiché
    const username = body.username ?? body.name ?? body.nom ?? body.displayName;
    if (username !== undefined) {
        const r = validateNom(username, false, 'Nom affiché');
        if (!r.valid) errors.push(r.error);
    }

    // Email
    const email = body.email ?? body.mail;
    if (email !== undefined) {
        const r = validateEmail(email, false);
        if (!r.valid) errors.push(r.error);
    }

    // Téléphone
    const phone = body.phone ?? body.telephone ?? body.mobile ?? body.phoneNumber;
    if (phone !== undefined && String(phone || '').trim()) {
        const r = validatePhone(phone, false);
        if (!r.valid) errors.push(r.error);
    }

    // Société / companyId (nom libre)
    const company = body.companyId ?? body.companyName ?? body.company ?? body.organization;
    if (company !== undefined) {
        const r = validateText(company, { max: 150, label: 'Société' });
        if (!r.valid) errors.push(r.error);
    }

    // Spécialité
    const specialite = body.specialite ?? body.speciality ?? body.specialty ?? body.poste ?? body.title ?? body.jobTitle;
    if (specialite !== undefined) {
        const r = validateText(specialite, { max: 150, label: 'Spécialité' });
        if (!r.valid) errors.push(r.error);
    }

    // URL photo — accepte http/https ou data: URI
    const imageUrl = body.imageUrl ?? body.photoUrl ?? body.avatarUrl;
    if (imageUrl !== undefined && String(imageUrl || '').trim()) {
        const v = String(imageUrl).trim();
        if (!URL_REGEX.test(v) && !v.toLowerCase().startsWith('data:image/') && !v.startsWith('/uploads/')) {
            errors.push('URL photo invalide – doit commencer par http://, https://, data:image/ ou /uploads/');
        }
    }

    // URL site web
    const websiteUrl = body.websiteUrl ?? body.siteWeb ?? body.website ?? body.url;
    if (websiteUrl !== undefined && String(websiteUrl || '').trim()) {
        const r = validateUrl(websiteUrl, false, 'URL site web');
        if (!r.valid) errors.push(r.error);
    }

    // URL profil (LinkedIn / Portfolio)
    const profileUrl = body.profileUrl ?? body.linkedinUrl ?? body.portfolioUrl;
    if (profileUrl !== undefined && String(profileUrl || '').trim()) {
        const r = validateUrl(profileUrl, false, 'URL profil');
        if (!r.valid) errors.push(r.error);
    }

    // Adresse
    const address = body.address ?? body.adresse ?? body.street ?? body.location;
    if (address !== undefined) {
        const r = validateText(address, { max: 255, label: 'Adresse' });
        if (!r.valid) errors.push(r.error);
    }

    // Mot de passe
    if (body.password !== undefined && String(body.password || '').trim()) {
        const r = validatePassword(body.password, false);
        if (!r.valid) errors.push(r.error);
    }

    return errors;
}

/**
 * Valide un login (POST /api/login).
 */
function validateLogin(body = {}) {
    const errors = [];
    const emailR = validateEmail(body.email, true);
    if (!emailR.valid) errors.push(emailR.error);
    if (!String(body.password || '').trim()) errors.push('Mot de passe obligatoire');
    return errors;
}

/**
 * Valide la création d'un concepteur par un admin.
 */
function validateCreateConcepteur(body = {}) {
    const errors = [];
    const emailR = validateEmail(body.email, true);
    if (!emailR.valid) errors.push(emailR.error);
    const nomR = validateNom(body.username ?? body.name ?? body.nom, true, 'Nom');
    if (!nomR.valid) errors.push(nomR.error);
    const pwR = validatePassword(body.password, true);
    if (!pwR.valid) errors.push(pwR.error);
    return errors;
}

/**
 * Valide la création d'un client (auto-inscription).
 */
function validateClientSelfRegister(body = {}) {
    const errors = [];
    const emailR = validateEmail(body.email, true);
    if (!emailR.valid) errors.push(emailR.error);
    const nomR = validateNom(body.name ?? body.nom, true, 'Nom');
    if (!nomR.valid) errors.push(nomR.error);
    const pwR = validatePassword(body.password, true);
    if (!pwR.valid) errors.push(pwR.error);
    return errors;
}

/**
 * Valide les données d'une nouvelle machine.
 */
function validateCreateMachine(body = {}) {
    const errors = [];
    const nomR = validateNom(body.name, true, 'Nom de la machine');
    if (!nomR.valid) errors.push(nomR.error);
    return errors;
}

/**
 * Valide les champs de mise à jour d'une machine.
 */
function validateUpdateMachine(body = {}) {
    const errors = [];
    if (body.name !== undefined) {
        const r = validateNom(body.name, false, 'Nom de la machine');
        if (!r.valid) errors.push(r.error);
    }
    if (body.imageUrl !== undefined && String(body.imageUrl || '').trim()) {
        const v = String(body.imageUrl).trim();
        if (!URL_REGEX.test(v) && !v.toLowerCase().startsWith('data:image/') && !v.startsWith('/uploads/')) {
            errors.push('imageUrl invalide');
        }
    }
    return errors;
}

module.exports = {
    createValidationError,
    validateEmail,
    validatePhone,
    validateUrl,
    validateNom,
    validatePassword,
    validateText,
    validateConcepteurProfileUpdate,
    validateLogin,
    validateCreateConcepteur,
    validateClientSelfRegister,
    validateCreateMachine,
    validateUpdateMachine,
};
