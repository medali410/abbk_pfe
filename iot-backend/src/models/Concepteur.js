const mongoose = require('mongoose');

/**
 * Personne « concepteur » (connexion + Observatory) — collection MongoDB `concepteurs`.
 *
 * À ne pas confondre avec :
 * - [Conception] : documents CAO / manuels (collection `conceptions`)
 * - [Technician] : techniciens terrain (collection `technicians`)
 * - [User] : super-admin / admin société uniquement (plus de rôle CONCEPTION ici)
 */
const concepteurSchema = new mongoose.Schema(
    {
        email: { type: String, required: true, unique: true, trim: true, lowercase: true },
        username: { type: String, required: true, unique: true, trim: true },
        password: { type: String, required: true },
        companyId: { type: String },
        machineIds: [{ type: String }],
        location: { type: String },
        specialite: { type: String },
        imageUrl: { type: String },
    },
    {
        timestamps: true,
        collection: 'concepteurs',
        toJSON: {
            virtuals: true,
            versionKey: false,
            transform(_doc, ret) {
                ret.id = ret._id != null ? String(ret._id) : ret.id;
                delete ret._id;
                delete ret.password;
            },
        },
        toObject: {
            virtuals: true,
            versionKey: false,
            transform(_doc, ret) {
                ret.id = ret._id != null ? String(ret._id) : ret.id;
                delete ret._id;
                delete ret.password;
            },
        },
    }
);

module.exports = mongoose.model('Concepteur', concepteurSchema);
