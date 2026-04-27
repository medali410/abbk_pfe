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
      // Incrémenter les machines RUNNING
      await Machine.updateMany(
        { status: 'RUNNING' },
        {
          $inc: { 'tempsMarche.totalHeures': 1 / 60 },
          $set: {
            'tempsMarche.derniereMiseAJour': new Date(),
            'tempsMarche.enMarche': true
          }
        }
      );

      // Marquer les machines à l'arrêt
      await Machine.updateMany(
        { status: { $ne: 'RUNNING' } },
        {
          $set: {
            'tempsMarche.enMarche': false,
            'tempsMarche.derniereMiseAJour': new Date()
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

