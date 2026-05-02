const Machine = require('../models/Machine');
const Controle = require('../models/Controle');

// ---------------------------------------------------------------
// Priorité → label couleur lisible dans Flutter
// ---------------------------------------------------------------
function prioriteLabel(priorite) {
  switch (priorite) {
    case 'urgente':  return 'URGENTE 🔴';
    case 'haute':    return 'HAUTE 🟠';
    case 'normale':  return 'NORMALE 🟡';
    case 'basse':    return 'BASSE 🟢';
    default:         return priorite || 'NORMALE';
  }
}

/**
 * Démarre le service de contrôle périodique.
 * @param {import('socket.io').Server} [io]  - Instance Socket.IO (optionnelle).
 *   Si fournie, un événement `nouveau_controle` est émis à tous les clients
 *   connectés dès qu'un contrôle est généré automatiquement.
 */
const startControleService = (io) => {
  setInterval(async () => {
    try {
      const machines = await Machine.find({});

      for (let machine of machines) {
        // Sécurité si tempsMarche n'est pas encore défini
        const totalHeures = machine.tempsMarche ? machine.tempsMarche.totalHeures : 0;

        if (!machine.seuilsControle || machine.seuilsControle.length === 0) continue;

        for (let seuil of machine.seuilsControle) {
          // ✅ Seuil atteint ?
          if (seuil.prochainControleHeure != null && totalHeures >= seuil.prochainControleHeure) {

            // Vérifier si contrôle déjà créé
            const controleExiste = await Controle.findOne({
              machineId: machine._id,
              typeControle: seuil.typeControle,
              typeMaintenance: 'preventive',
              statut: { $in: ['en_attente', 'assignée', 'planifié', 'en_cours'] }
            });

            if (!controleExiste) {
              // ✅ Créer le contrôle automatiquement
              const nouveauControle = await Controle.create({
                machineId: machine._id,
                machineName: machine.name,
                typeControle: seuil.typeControle,
                elementControle: seuil.typeControle,
                typeMaintenance: 'preventive',
                intervalleHeures: Number(seuil.intervalleHeures || 0),
                prochainControleHeure: Number(seuil.prochainControleHeure || totalHeures),
                heuresDeClenchement: Number(seuil.prochainControleHeure || totalHeures),
                tempsMarcheTotalHeures: totalHeures,
                dateControle: new Date(),
                datePrevue: new Date(),
                priorite: seuil.priorite,
                statut: 'en_attente',
                motorType: machine.motorType
              });

              console.log(`✅ Contrôle créé : ${seuil.typeControle} pour ${machine.name}`);

              // ✅ Notification temps réel Socket.IO
              if (io) {
                const payload = {
                  _id:          String(nouveauControle._id),
                  id:           String(nouveauControle._id),
                  controleId:   String(nouveauControle._id),
                  machineId:    String(machine._id),
                  machineName:  machine.name,
                  typeControle: seuil.typeControle,
                  heures:       totalHeures,
                  priorite:     seuil.priorite,
                  prioriteLabel: prioriteLabel(seuil.priorite),
                  motorType:    machine.motorType,
                  dateControle: nouveauControle.dateControle,
                  datePrevue: nouveauControle.datePrevue,
                  elementControle: nouveauControle.elementControle,
                  statut: nouveauControle.statut,
                  declencheParHeuresMarche: true,
                };
                io.emit('nouveau_controle', payload);
                console.log(`🔔 Socket.IO → nouveau_controle émis pour ${machine.name}`);
              }
            }
          }
        }
      }
    } catch (error) {
      console.error('❌ Erreur controleService:', error);
    }
  }, 60000); // chaque 1 minute
};

module.exports = { startControleService };
