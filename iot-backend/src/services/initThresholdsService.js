const Machine = require('../models/Machine');

const seuilsAirCooled = [
  { typeControle: 'Contrôle filtre air', intervalleHeures: 50, prochainControleHeure: 50, priorite: 'normale' },
  { typeControle: 'Contrôle huile', intervalleHeures: 100, prochainControleHeure: 100, priorite: 'haute' },
  { typeControle: 'Contrôle courroie', intervalleHeures: 250, prochainControleHeure: 250, priorite: 'normale' },
  { typeControle: 'Nettoyage radiateur', intervalleHeures: 300, prochainControleHeure: 300, priorite: 'normale' },
  { typeControle: 'Révision générale', intervalleHeures: 500, prochainControleHeure: 500, priorite: 'haute' },
  { typeControle: 'Remplacement filtre air', intervalleHeures: 1000, prochainControleHeure: 1000, priorite: 'urgente' }
];

const seuilsWaterCooled = [
  { typeControle: 'Contrôle niveau eau', intervalleHeures: 50, prochainControleHeure: 50, priorite: 'haute' },
  { typeControle: 'Contrôle pompe eau', intervalleHeures: 100, prochainControleHeure: 100, priorite: 'haute' },
  { typeControle: 'Vérification circuit eau', intervalleHeures: 200, prochainControleHeure: 200, priorite: 'normale' },
  { typeControle: 'Changement liquide refroidissement', intervalleHeures: 500, prochainControleHeure: 500, priorite: 'haute' },
  { typeControle: 'Contrôle joints', intervalleHeures: 750, prochainControleHeure: 750, priorite: 'normale' },
  { typeControle: 'Révision générale', intervalleHeures: 1000, prochainControleHeure: 1000, priorite: 'urgente' }
];

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

      // 4. Ajouter automatiquement les seuils si le tableau est vide
      if (!machine.seuilsControle || machine.seuilsControle.length === 0) {
        const defaultThresholds = machine.motorType === 'water_cooled' ? seuilsWaterCooled : seuilsAirCooled;
        
        // On clone les seuils pour éviter les références partagées
        machine.seuilsControle = defaultThresholds.map(s => ({
          ...s,
          derniereVerificationHeure: 0
        }));
        
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
