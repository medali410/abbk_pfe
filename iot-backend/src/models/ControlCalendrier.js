const mongoose = require('mongoose');

/**
 * Journal des saisies « Compte rendu de visite » depuis le calendrier technicien (bouton Valider).
 * Collection MongoDB : control_calendrier
 */
const controlCalendrierSchema = new mongoose.Schema(
  {
    machineId: { type: String, required: true },
    machineName: { type: String, default: '' },
    /** Date du jour sélectionné dans le calendrier (YYYY-MM-DD, UTC logique métier). */
    jour: { type: String, required: true },
    /** Texte saisi par le technicien. */
    compteRendu: { type: String, required: true },
    technicienId: { type: mongoose.Schema.Types.ObjectId, default: null },
    technicienNom: { type: String, default: '' },
    /** Lien vers la fiche [Controle] créée ou mise à jour pour cette validation. */
    controleId: { type: mongoose.Schema.Types.ObjectId, ref: 'Controle', default: null },
    source: { type: String, default: 'calendrier_technicien' },
  },
  { timestamps: true, collection: 'control_calendrier' }
);

module.exports = mongoose.model('ControlCalendrier', controlCalendrierSchema);
