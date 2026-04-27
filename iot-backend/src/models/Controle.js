const mongoose = require('mongoose');

const controleSchema = new mongoose.Schema({
  machineId: { 
    type: String, // Correspond au format 'MAC-XXXX' utilisé dans le modèle Machine
    ref: 'Machine' 
  },
  machineName: { type: String },
  technicienId: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User',
    default: null
  },
  typeControle: { type: String },
  motorType: { 
    type: String,
    enum: ['air_cooled', 'water_cooled']
  },
  heuresDeClenchement: { type: Number },
  dateControle: { type: Date },
  priorite: { 
    type: String,
    enum: ['basse', 'normale', 'haute', 'urgente'],
    default: 'normale'
  },
  statut: { 
    type: String,
    enum: ['planifié', 'en_cours', 'terminé', 'annulé'],
    default: 'planifié'
  },
  notes: { type: String, default: '' }
}, { timestamps: true });

module.exports = mongoose.model('Controle', controleSchema);
