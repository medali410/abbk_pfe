const Machine = require('../models/Machine');

/**
 * Démarre le service de temps de marche.
 * @param {import('socket.io').Server} [io] - Instance Socket.IO optionnelle.
 *   Émet `temps_marche_update` chaque minute avec la liste des machines
 *   et leurs heures courantes.
 */
const startTempseMarcheService = (io) => {
  setInterval(async () => {
    try {
      const now = new Date();
      // Première minute en RUNNING sans horodatage : ancrer le début de session
      await Machine.updateMany(
        { status: 'RUNNING', 'tempsMarche.debutSessionMarche': { $in: [null, undefined] } },
        { $set: { 'tempsMarche.debutSessionMarche': now } }
      );

      // Incrémenter les machines RUNNING uniquement (temps de fonctionnement réel)
      await Machine.updateMany(
        { status: 'RUNNING' },
        {
          $inc: { 'tempsMarche.totalHeures': 1 / 60 },
          $set: {
            'tempsMarche.derniereMiseAJour': now,
            'tempsMarche.enMarche': true
          }
        }
      );

      // Marquer les machines à l'arrêt — pas d'avancement du compteur ; fin de session
      await Machine.updateMany(
        { status: { $ne: 'RUNNING' } },
        {
          $set: {
            'tempsMarche.enMarche': false,
            'tempsMarche.derniereMiseAJour': now,
            'tempsMarche.debutSessionMarche': null
          }
        }
      );

      console.log('✅ Temps de marche mis à jour');

      // ── Broadcast Socket.IO ─────────────────────────────────────────────────
      if (io) {
        const machines = await Machine.find({})
          .select('_id name status tempsMarche')
          .lean();

        const updates = machines.map((m) => ({
          machineId:   String(m._id),
          machineName: m.name,
          status:      m.status,
          totalHeures: m.tempsMarche?.totalHeures ?? 0,
          enMarche:    m.tempsMarche?.enMarche ?? false,
          debutSessionMarche: m.tempsMarche?.debutSessionMarche ?? null,
          ts:          new Date().toISOString(),
        }));

        io.emit('temps_marche_update', updates);
      }
      // ────────────────────────────────────────────────────────────────────────
    } catch (error) {
      console.error('❌ Erreur tempsMarche:', error);
    }
  }, 60000); // chaque 1 minute
};

module.exports = { startTempseMarcheService };

