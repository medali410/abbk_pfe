const mongoose = require('mongoose');

/**
 * Documents de conception (CAO, schémas, manuels) — collection MongoDB: `conceptions`.
 * Les personnes « concepteur » (connexion app) sont dans la collection `concepteurs` (modèle [Concepteur]).
 */
const ConceptionSchema = new mongoose.Schema({
    name: { type: String, required: true },
    version: { type: String, default: 'v1.0' },
    company: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: false },
    /** Client métier (ex. CLI-2026-xxx) qui pilote les machines concernées */
    clientId: { type: String },
    documentType: { type: String, enum: ['Plan mécanique', 'Schéma électrique', 'Rapport technique', 'Manuel maintenance'], required: true },
    securityEmail: { type: String },
    password: { type: String },
    status: { type: String, default: 'BROUILLON' },
    completionScore: { type: Number, default: 75 },
    fileName: { type: String },
    fileSize: { type: String }
}, {
    collection: 'conceptions',
    timestamps: true,
    toJSON: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            ret.id = ret._id;
            delete ret._id;
            delete ret.password;
        }
    }
});

module.exports = mongoose.model('Conception', ConceptionSchema);
