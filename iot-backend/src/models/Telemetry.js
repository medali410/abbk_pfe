const mongoose = require('mongoose');

const TelemetrySchema = new mongoose.Schema({
    machineId: { type: String, ref: 'Machine', required: true },
    // Legacy fields (kept for backward compatibility)
    temperature: { type: Number },
    vibration: { type: Number },
    powerConsumption: { type: Number },
    proximity: { type: Number },
    // Generic metrics map: keys match sensor parameter keys
    // e.g. { thermal: 72.3, pressure: 1.2, power: 45, ultrasonic: 15, presence: 1, magnetic: 20, infrared: 55 }
    metrics: { type: Map, of: Number, default: {} },
    /** Scénario « avant panne » dérivé des 7 paramètres + historique */
    failureScenario: {
        scenarioCode: { type: String },
        scenarioLabel: { type: String },
        scenarioProbPanne: { type: Number },
        scenarioExplanation: { type: String },
        basedOnSamples: { type: Number },
        scenarioThermalSeries: [{ type: Number }],
    },
}, {
    timestamps: true,
    toJSON: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            delete ret._id;
        }
    }
}); // createdAt acts as the timestamp

module.exports = mongoose.model('Telemetry', TelemetrySchema);
