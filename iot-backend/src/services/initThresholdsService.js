const Machine = require('../models/Machine');
const { ensureMotorSensorRoutineSeuil, ensureCondensateurRoutineSeuil } = require('../utils/motorSensorRoutineSeuil');

const initializeExistingMachines = async () => {
  try {
    console.log('⏳ Vérification de l\'initialisation des seuils machines...');
    
    // 1. Récupérer toutes les machines
    const machines = await Machine.find({});
    let updateCount = 0;

    for (let machine of machines) {
      let hasChanged = false;

      // 2. Si motorType est vide ou invalide (ancien format EL_M) → mettre "air_cooled"
      const currentMotorType = machine.motorType;
      if (!['air_cooled', 'water_cooled'].includes(currentMotorType)) {
        machine.motorType = 'air_cooled';
        hasChanged = true;
      }

      // 3. Initialiser tempsMarche à 0 si non défini
      if (!machine.tempsMarche || machine.tempsMarche.totalHeures === undefined) {
        machine.tempsMarche = {
          totalHeures: 0,
          derniereMiseAJour: new Date(),
          enMarche: false
        };
        hasChanged = true;
      }

      // 4. Seuils par défaut : uniquement maintenance préventive par temps de marche
      //    (condensateurs + routine moteur). Pas de liste filtre/huile/courroie générique.
      if (!machine.seuilsControle || machine.seuilsControle.length === 0) {
        machine.seuilsControle = [];
        hasChanged = true;
      }

      // 5. Remplit condensateurs (72 h) + routine capteurs moteur (168 h) si absents
      if (ensureMotorSensorRoutineSeuil(machine) || ensureCondensateurRoutineSeuil(machine)) {
        hasChanged = true;
      }

      if (hasChanged) {
        await machine.save();
        updateCount++;
      }
    }

    if (updateCount > 0) {
      console.log(`✅ Initialisation terminée : ${updateCount} machines mises à jour.`);
    } else {
      console.log('ℹ️ Toutes les machines sont déjà initialisées.');
    }
  } catch (error) {
    console.error('❌ Erreur lors de l\'initialisation des machines:', error);
  }
};

module.exports = { initializeExistingMachines };
