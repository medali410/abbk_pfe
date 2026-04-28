const mongoose = require('mongoose');

const PurchaseRequestSchema = new mongoose.Schema(
    {
        machineId: { type: String, required: true, trim: true },
        machineName: { type: String, default: '' },
        requesterName: { type: String, required: true, trim: true },
        requesterEmail: { type: String, default: '', trim: true, lowercase: true },
        requesterPhone: { type: String, default: '', trim: true },
        location: { type: String, default: '', trim: true },
        googleMapsUrl: { type: String, default: '', trim: true },
        note: { type: String, default: '', trim: true },
        status: {
            type: String,
            enum: ['PENDING', 'VALIDATED', 'REJECTED'],
            default: 'PENDING',
        },
        reviewedById: { type: String, default: '' },
        reviewedByRole: { type: String, default: '' },
        reviewedByName: { type: String, default: '' },
        reviewedAt: { type: Date, default: null },
        linkedClientId: { type: String, default: '' },
        linkedTechnicianId: { type: String, default: '' },
        linkedMaintenanceAgentId: { type: String, default: '' },
    },
    {
        timestamps: true,
        toJSON: {
            virtuals: true,
            versionKey: false,
            transform(_doc, ret) {
                if (ret._id) {
                    ret.id = String(ret._id);
                    delete ret._id;
                }
                return ret;
            },
        },
    }
);

module.exports = mongoose.model('PurchaseRequest', PurchaseRequestSchema);
