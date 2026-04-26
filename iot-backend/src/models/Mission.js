const mongoose = require('mongoose');

const MissionSchema = new mongoose.Schema({
    interventionId: { type: mongoose.Schema.Types.ObjectId, ref: 'DiagnosticIntervention', required: true },
    machineId: { type: String, required: true },
    content: { type: String, required: true },
    missionId: { type: String, default: '' }, // Identifiant personnalisé (ex: TEST-001)
    missionStatus: { 
        type: String, 
        enum: ['SENT', 'CONFIRMED', 'COMPLETED'], 
        default: 'SENT' 
    },
    authorId: { type: String, default: '' },
    authorRole: { type: String, default: '' },
    authorName: { type: String, default: '' },
    noteId: { type: mongoose.Schema.Types.ObjectId, required: true }, // Lien vers la note spécifique dans l'intervention
}, {
    timestamps: true,
});

module.exports = mongoose.model('Mission', MissionSchema);
