const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
    email: { type: String, required: true, unique: true },
    username: { type: String, required: true, unique: true },
    password: { type: String, required: true }, // In production, hash this!
    /** Super-admin / admin flotte. Les concepteurs métier sont dans la collection `concepteurs` ([Concepteur]). */
    role: { type: String, enum: ['SUPER_ADMIN', 'COMPANY_ADMIN', 'TECHNICIAN'], default: 'TECHNICIAN' },
    companyId: { type: String },
    /** Machines autorisées pour arrêt / pilotage (vide = toutes les machines du client référencé par companyId). */
    machineIds: [{ type: String }],
    location: { type: String },
    /** Spécialisation affichée pour les comptes conception / maintenance */
    specialite: { type: String },
}, {
    timestamps: true,
    toJSON: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            delete ret._id;
            delete ret.password; // Also remove password from output
        }
    },
    toObject: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            delete ret._id;
            delete ret.password;
        }
    }
});

module.exports = mongoose.model('User', UserSchema);
