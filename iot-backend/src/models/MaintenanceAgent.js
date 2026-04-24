const mongoose = require('mongoose');

/**
 * Personnel maintenance (fiche métier) — distinct du technicien terrain.
 * Géré par le super-admin ; mot de passe stocké hashé pour usage futur (connexion).
 */
const MaintenanceAgentSchema = new mongoose.Schema({
    maintenanceAgentId: { type: String, required: true, unique: true, index: true },
    firstName: { type: String, required: true, trim: true },
    lastName: { type: String, required: true, trim: true },
    email: { type: String, required: true, trim: true, lowercase: true, unique: true },
    password: { type: String, required: true },
    address: { type: String, trim: true, default: '' },
    /** Ville, région ou site d’intervention */
    location: { type: String, trim: true, default: '' },
    /** Référence client (clientId métier CLI-… ou ObjectId Mongo) */
    clientId: { type: String, required: true },
    /** IDs machines Mongo (_id) rattachées au client choisi */
    machineIds: { type: [String], default: [] },
}, {
    timestamps: true,
    toJSON: {
        virtuals: true,
        versionKey: false,
        transform(_doc, ret) {
            delete ret.password;
            if (ret._id) {
                ret.id = String(ret._id);
                delete ret._id;
            }
            return ret;
        },
    },
    toObject: {
        virtuals: true,
        versionKey: false,
        transform(_doc, ret) {
            delete ret.password;
            return ret;
        },
    },
});

MaintenanceAgentSchema.virtual('fullName').get(function () {
    return `${this.firstName || ''} ${this.lastName || ''}`.trim();
});

module.exports = mongoose.model('MaintenanceAgent', MaintenanceAgentSchema);
