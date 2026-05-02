const mongoose = require('mongoose');
const crypto = require('crypto');

function generateMachineId() {
    const hex = crypto.randomBytes(4).toString('hex').toUpperCase();
    return `MAC-${hex}`;
}

const ParameterSchema = new mongoose.Schema({
    key: { type: String, required: true },
    label: { type: String, required: true },
    unit: { type: String, default: '' },
    enabled: { type: Boolean, default: false },
    warnThreshold: { type: Number, default: null },
    criticalThreshold: { type: Number, default: null },
    icon: { type: String, default: 'sensors' },
}, { _id: false });

const MachineSchema = new mongoose.Schema({
    _id: { type: String, default: generateMachineId },
    name: { type: String, required: true },
    type: { type: String, default: '' },
    power: { type: String, default: '0 kW' },
    voltage: { type: String, default: '0V' },
    speed: { type: String, default: '0 tr/min' },
    motorType: { 
        type: String, 
        enum: ['air_cooled', 'water_cooled', 'electric', 'diesel', 'EL_M'],
        default: 'air_cooled'
    },
    seuilsControle: [
        {
            typeControle: { type: String },
            intervalleHeures: { type: Number },
            derniereVerificationHeure: { type: Number, default: 0 },
            prochainControleHeure: { type: Number },
            priorite: { 
                type: String, 
                enum: ['basse', 'normale', 'haute', 'urgente'],
                default: 'normale'
            }
        }
    ],
    /**
     * Multiplicateur indicatif : heures_intervention_affichees ≈ rul_estime (sortie modèle) × ce facteur.
     * À régler par superadmin selon le parc (pas une vérité physique ; calibration métier).
     * null / 0 = pas de conversion heures (seule la valeur modèle brute est exposée).
     */
    rulHoursPerModelUnit: { type: Number, default: null },
    installDate: { type: String, default: '' },
    thresholds: { type: Object, default: {} },
    status: {
        type: String,
        enum: ['RUNNING', 'STOPPED', 'MAINTENANCE', 'normal'],
        default: 'STOPPED'
    },
    tempsMarche: {
        totalHeures: { type: Number, default: 0 },
        derniereMiseAJour: { type: Date, default: null },
        enMarche: { type: Boolean, default: false },
        /** Début de la session de marche courante (RUNNING). Effacé à l’arrêt — le compteur d’heures ne progresse qu’en RUNNING. */
        debutSessionMarche: { type: Date, default: null },
    },
    maintenanceControlActive: { type: Boolean, default: false },
    maintenanceControlBy: { type: String, default: '' },
    maintenanceControlById: { type: String, default: '' },
    maintenanceControlStartedAt: { type: Date, default: null },
    maintenanceControlEndsAt: { type: Date, default: null },
    location: { type: String, required: false },
    // URL / nom du modèle 3D saisi depuis le dashboard conception.
    model3dUrl: { type: String, default: '' },
    lastMaintenance: { type: Date },
    // Peut rester vide tant que la machine n'est pas encore vendue/assignée à un client.
    companyId: { type: String, required: false, default: '' },
    registeredVia: { type: String, enum: ['dashboard', 'arduino', 'api'], default: 'dashboard' },
    firmwareVersion: { type: String, default: '' },
    parameters: {
        type: [ParameterSchema],
        default: [
            { key: 'thermal', label: 'Température', unit: '°C', enabled: true, warnThreshold: 70, criticalThreshold: 85, icon: 'device-thermostat' },
            { key: 'pressure', label: 'Pression', unit: 'bar', enabled: false, warnThreshold: 3, criticalThreshold: 5, icon: 'speed' },
            { key: 'power', label: 'Puissance', unit: 'A', enabled: false, warnThreshold: 50, criticalThreshold: 80, icon: 'flash-on' },
            { key: 'ultrasonic', label: 'Ultrason', unit: 'cm', enabled: false, warnThreshold: 20, criticalThreshold: 10, icon: 'settings-input-antenna' },
            { key: 'presence', label: 'Présence', unit: '', enabled: false, warnThreshold: null, criticalThreshold: null, icon: 'person-pin' },
            { key: 'magnetic', label: 'Magnétique', unit: 'mT', enabled: false, warnThreshold: 50, criticalThreshold: 100, icon: 'radio-button-checked' },
            { key: 'infrared', label: 'Infrarouge', unit: '°C', enabled: false, warnThreshold: 60, criticalThreshold: 80, icon: 'wb-sunny' },
        ]
    },
}, {
    timestamps: true,
    toJSON: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            if (ret._id != null) ret.id = String(ret._id);
            delete ret._id;
        }
    },
    toObject: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            if (ret._id != null) ret.id = String(ret._id);
            delete ret._id;
        }
    }
});

function normalizeSeuilsControle(seuils) {
    if (!Array.isArray(seuils)) return seuils;
    return seuils.map((s) => {
        const iv = Number(s.intervalleHeures || 0);
        const dv = Number(s.derniereVerificationHeure ?? 0);
        const computedNext = dv + iv;
        const prochain =
            s.prochainControleHeure != null && s.prochainControleHeure !== ''
                ? Number(s.prochainControleHeure)
                : computedNext;
        return {
            ...s,
            intervalleHeures: iv,
            derniereVerificationHeure: dv,
            prochainControleHeure: Number.isFinite(prochain) ? prochain : computedNext,
        };
    });
}

MachineSchema.pre('save', function (next) {
    if (this.seuilsControle && Array.isArray(this.seuilsControle)) {
        this.seuilsControle = normalizeSeuilsControle(this.seuilsControle);
    }
    next();
});

const Machine = mongoose.model('Machine', MachineSchema);
Machine.normalizeSeuilsControle = normalizeSeuilsControle;
module.exports = Machine;
