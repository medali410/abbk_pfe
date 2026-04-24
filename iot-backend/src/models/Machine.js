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
    /** EL_S | EL_M | EL_L — entrée embedding du modèle IA (aligné dataset AI4I L/M/H). */
    motorType: { type: String, default: 'EL_M' },
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
    maintenanceControlActive: { type: Boolean, default: false },
    maintenanceControlBy: { type: String, default: '' },
    maintenanceControlById: { type: String, default: '' },
    maintenanceControlStartedAt: { type: Date, default: null },
    maintenanceControlEndsAt: { type: Date, default: null },
    location: { type: String, required: false },
    lastMaintenance: { type: Date },
    companyId: { type: String, required: true },
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

module.exports = mongoose.model('Machine', MachineSchema);
