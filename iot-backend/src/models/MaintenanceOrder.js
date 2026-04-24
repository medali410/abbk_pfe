const mongoose = require('mongoose');

const MaintenanceOrderSchema = new mongoose.Schema({
    machineId: { type: String, required: true },
    technicianId: { type: String },
    companyId: { type: String, required: true },
    type: {
        type: String,
        enum: ['CORRECTIVE', 'PREVENTIVE', 'PREDICTIVE', 'EMERGENCY', 'IMPROVEMENT'],
        default: 'CORRECTIVE'
    },
    description: { type: String, required: true },
    rootCause: { type: String, default: '' },
    actionTaken: { type: String, default: '' },
    closeNote: { type: String, default: '' },
    downtimeMinutes: { type: Number, default: null },
    startedAt: { type: Date, default: null },
    closedAt: { type: Date, default: null },
    status: {
        type: String,
        enum: ['PENDING', 'IN_PROGRESS', 'COMPLETED'],
        default: 'PENDING'
    },
    priority: {
        type: String,
        enum: ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'],
        default: 'MEDIUM'
    }
}, {
    timestamps: true,
    toJSON: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            delete ret._id;
        }
    },
    toObject: {
        virtuals: true,
        versionKey: false,
        transform: function (doc, ret) {
            delete ret._id;
        }
    }
});

module.exports = mongoose.model('MaintenanceOrder', MaintenanceOrderSchema);
