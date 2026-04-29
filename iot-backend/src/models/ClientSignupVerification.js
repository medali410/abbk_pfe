const mongoose = require('mongoose');

/**
 * Code à 6 chiffres pour valider l’inscription client par email (Jetable après usage ou TTL).
 */
const schema = new mongoose.Schema(
    {
        email: { type: String, required: true, lowercase: true, trim: true, index: true },
        codeHash: { type: String, required: true },
        expiresAt: { type: Date, required: true },
    },
    { timestamps: true, collection: 'client_signup_verifications' }
);

schema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('ClientSignupVerification', schema);
