const mongoose = require('mongoose');

const InterventionArchiveSchema = new mongoose.Schema(
    {
        interventionId: { type: String, required: true, unique: true, index: true },
        machineId: { type: String, required: true, index: true },
        companyId: { type: String, required: true, index: true },
        scenarioType: { type: String, default: '' },
        scenarioLabel: { type: String, default: '' },
        summary: { type: String, default: '' },
        finalDecision: { type: String, default: '' },
        finalNote: { type: String, default: '' },
        status: { type: String, default: 'DONE' },
        startedAt: { type: Date, default: null },
        finishedAt: { type: Date, default: null },
        technicianId: { type: String, default: '' },
        technicianName: { type: String, default: '' },
        messages: { type: [mongoose.Schema.Types.Mixed], default: [] },
        coordinationNotes: { type: [mongoose.Schema.Types.Mixed], default: [] },
        steps: { type: [mongoose.Schema.Types.Mixed], default: [] },
        missions: { type: [mongoose.Schema.Types.Mixed], default: [] },
        recipientsNotified: { type: [String], default: [] },
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

module.exports = mongoose.model('InterventionArchive', InterventionArchiveSchema);
