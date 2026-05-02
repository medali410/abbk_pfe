/**
 * Crée un contrôle préventif ouvert pour une machine dont le nom contient une chaîne (ex. alfa).
 * Utile si aucun contrôle n’apparaît dans le calendrier alors que la machine existe.
 *
 * Usage : node ensure_open_controle_for_machine.js [partie_du_nom]
 * Défaut partie_du_nom = alfa
 */
require('dotenv').config();
const mongoose = require('mongoose');
const Machine = require('./src/models/Machine');
const Controle = require('./src/models/Controle');
const { ROUTINE_TYPE, ROUTINE_INTERVAL_HOURS } = require('./src/utils/motorSensorRoutineSeuil');

const partial = process.argv[2] || 'alfa';

async function main() {
    const uri = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/dali_pfe';
    await mongoose.connect(uri);
    const escaped = partial.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const rx = new RegExp(escaped, 'i');
    const machine = await Machine.findOne({ name: rx });
    if (!machine) {
        console.error(`Aucune machine dont le nom contient « ${partial} ».`);
        await mongoose.disconnect();
        process.exit(1);
    }
    const mid = String(machine._id);
    const open = await Controle.findOne({
        machineId: mid,
        statut: { $in: ['en_attente', 'assignée', 'planifié', 'en_cours'] },
    });
    if (open) {
        console.log('Déjà un contrôle ouvert :', String(open._id), '|', open.typeControle, '|', machine.name);
        await mongoose.disconnect();
        return;
    }
    const total = Number(machine.tempsMarche?.totalHeures || 0);
    let seuilRow =
        Array.isArray(machine.seuilsControle) &&
        machine.seuilsControle.find((s) => String(s.typeControle || '').trim() === ROUTINE_TYPE);
    const seuilNum = Number(seuilRow?.prochainControleHeure ?? total + ROUTINE_INTERVAL_HOURS);

    const doc = await Controle.create({
        machineId: mid,
        machineName: machine.name,
        typeControle: ROUTINE_TYPE,
        elementControle: ROUTINE_TYPE,
        typeMaintenance: 'preventive',
        intervalleHeures: ROUTINE_INTERVAL_HOURS,
        prochainControleHeure: seuilNum,
        heuresDeClenchement: seuilNum,
        tempsMarcheTotalHeures: total,
        dateControle: new Date(),
        datePrevue: new Date(),
        priorite: 'normale',
        statut: 'en_attente',
        motorType: machine.motorType || 'electric',
    });
    console.log('Contrôle créé :', String(doc._id));
    console.log('Machine :', machine.name, '|', mid);
    await mongoose.disconnect();
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
