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
  technicienNom: { type: String, default: '' },
  typeControle: { type: String },
  elementControle: { type: String, default: '' },
  /** Aligné sur Machine.motorType (air_cooled, water_cooled, electric, diesel, EL_M, …) */
  motorType: { type: String, default: '' },
  typeMaintenance: {
    type: String,
    enum: ['preventive', 'corrective'],
    default: 'preventive',
  },
  intervalleHeures: { type: Number, default: 0 },
  prochainControleHeure: { type: Number, default: 0 },
  heuresDeClenchement: { type: Number },
  tempsMarcheTotalHeures: { type: Number, default: 0 },
  dateControle: { type: Date },
  datePrevue: { type: Date, default: null },
  dateRealisation: { type: Date, default: null },
  assignedAt: { type: Date, default: null },
  startedAt: { type: Date, default: null },
  completedAt: { type: Date, default: null },
  priorite: { 
    type: String,
    enum: ['basse', 'normale', 'haute', 'urgente'],
    default: 'normale'
  },
  statut: { 
    type: String,
    enum: ['en_attente', 'assignée', 'planifié', 'en_cours', 'terminé', 'annulé'],
    default: 'en_attente'
  },
  notes: { type: String, default: '' },
  rapportControle: { type: mongoose.Schema.Types.Mixed, default: null }
}, { timestamps: true });

module.exports = mongoose.model('Controle', controleSchema);
