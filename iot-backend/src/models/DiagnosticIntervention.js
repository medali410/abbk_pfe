const mongoose = require('mongoose');

const StepSchema = new mongoose.Schema({
    order: { type: Number, required: true },
    title: { type: String, required: true },
    details: { type: String, default: '' },
    status: {
        type: String,
        enum: ['PENDING', 'DONE', 'BLOCKED', 'SKIPPED'],
        default: 'PENDING',
    },
    doneById: { type: String, default: '' },
    doneByRole: { type: String, default: '' },
    doneAt: { type: Date, default: null },
    note: { type: String, default: '' },
}, { _id: true });

const MessageSchema = new mongoose.Schema({
    authorId: { type: String, default: '' },
    authorRole: { type: String, default: '' },
    authorName: { type: String, default: '' },
    content: { type: String, required: true },
    messageType: { type: String, enum: ['TEXT', 'SYSTEM'], default: 'TEXT' },
    createdAt: { type: Date, default: Date.now },
}, { _id: true });

const DiagnosticInterventionSchema = new mongoose.Schema({
    machineId: { type: String, required: true },
    companyId: { type: String, required: true },
    scenarioType: { type: String, required: true },
    scenarioLabel: { type: String, required: true },
    summary: { type: String, default: '' },
    createdById: { type: String, default: '' },
    createdByRole: { type: String, default: '' },
    createdByName: { type: String, default: '' },
    technicianId: { type: String, default: '' },
    technicianName: { type: String, default: '' },
    status: {
        type: String,
        enum: ['OPEN', 'IN_PROGRESS', 'BLOCKED', 'DONE', 'CANCELLED'],
        default: 'OPEN',
    },
    currentStepIndex: { type: Number, default: 0 },
    finalDecision: {
        type: String,
        enum: ['', 'CAPTEUR_FAULT', 'REAL_MACHINE_FAULT', 'REAL_FAILURE', 'FALSE_ALARM'],
        default: '',
    },
    finalNote: { type: String, default: '' },
    steps: { type: [StepSchema], default: [] },
    messages: { type: [MessageSchema], default: [] },
    coordinationNotes: { type: [MessageSchema], default: [] },
    finishedAt: { type: Date, default: null },
}, {
    timestamps: true,
});

module.exports = mongoose.model('DiagnosticIntervention', DiagnosticInterventionSchema);
