const mongoose = require('mongoose');

const AlertSchema = new mongoose.Schema({
    machineId: { type: String, ref: 'Machine', required: true },
    machineName: { type: String }, // Optional
    severity: {
        type: String,
        enum: ['LOW', 'MEDIUM', 'HIGH'],
        required: true
    },
    type: {
        type: String,
        enum: ['THERMAL', 'PRESSURE', 'POWER', 'ULTRASONIC', 'PRESENCE', 'MAGNETIC', 'INFRARED', 'TEMPERATURE', 'VIBRATION', 'POWER_CONSUMPTION', 'MANUAL', 'AI_PREDICTION'],
        default: 'MANUAL'
    },
    message: { type: String, required: true },
    value: { type: Number }, // Optional measured value
    threshold: { type: Number }, // Optional threshold
    resolved: { type: Boolean, default: false },
    resolvedAt: { type: Date }
}, {
    timestamps: true,
    toJSON: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            delete ret._id;
        }
    }
});

module.exports = mongoose.model('Alert', AlertSchema);
