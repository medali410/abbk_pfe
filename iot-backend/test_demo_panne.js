/**
 * DALI PFE — Démo MQTT : machine Dzli (ou autre ID)
 *
 * Envoie des trames comme un ESP32 sur HiveMQ, topic `machines/<ID>/telemetry`.
 * Unités alignées dataset AI4I pour le modèle :
 *   - air_temperature / process_temperature : Kelvin (obligatoires pour le blend ML)
 *   - temperature : °C affichés dashboard (dérivés du blend K)
 *   - torque [Nm], rpm, power = torque*rpm, pressure = torque/rpm
 *
 * Phases : NORMAL → DÉGRADATION → PANNE (critique), puis cycle.
 *
 * Prérequis : Node iot-backend démarré (Mongo + relais ML). Machine existante en base.
 *
 * Usage :
 *   node test_demo_panne.js
 *   node test_demo_panne.js MAC-1775750118162
 *   node test_demo_panne.js MAC-1775750118162 2000
 */

const mqtt = require('mqtt');

const MACHINE_ID = process.argv[2] || 'MAC-1775750118162';
const SEND_INTERVAL = Math.max(800, parseInt(process.argv[3] || '3000', 10) || 3000);
const MQTT_BROKER = 'mqtt://broker.hivemq.com';

const PHASE_NORMAL = 60000;
const PHASE_DEGRAD = 90000;
const PHASE_PANNE = 60000;
const TOTAL_CYCLE = PHASE_NORMAL + PHASE_DEGRAD + PHASE_PANNE;

function rand(lo, hi) {
    return lo + Math.random() * (hi - lo);
}
function r1(v) {
    return Math.round(v * 10) / 10;
}
function r2(v) {
    return Math.round(v * 100) / 100;
}
function r3(v) {
    return Math.round(v * 1000) / 1000;
}

/** °C affichage = moyenne (T_air + T_process) en K, convertie */
function displayCFromK(airK, procK) {
    return r1((airK + procK) / 2 - 273.15);
}

function genNormal() {
    const airK = 297.8 + rand(0, 0.6);
    const procK = 308.2 + rand(-0.4, 0.5);
    const rpm = Math.round(rand(1480, 1540));
    const torque = r2(rand(41, 47));
    const toolWear = Math.round(rand(5, 28));
    return { airK, procK, rpm, torque, toolWear };
}

function genDegradation(p) {
    const airK = 298 + p * 2.5 + rand(-0.2, 0.2);
    const procK = 308.5 + p * 4.8 + rand(-0.3, 0.3) + Math.sin(p * 10) * 0.4;
    const rpm = Math.round(1500 + p * 80 + rand(-25, 25));
    const torque = r2(44 + p * 6 + rand(-0.5, 0.5));
    const toolWear = Math.round(30 + p * 90 + rand(-5, 8));
    return { airK, procK, rpm, torque, toolWear };
}

function genPanne(p) {
    const airK = 299.5 + p * 3 + rand(-0.3, 0.4);
    const procK = 311.2 + p * 6.5 + rand(-0.4, 0.5) + Math.sin(p * 14) * 0.6;
    const rpm = Math.round(1580 + p * 120 + rand(-40, 40));
    const torque = r2(52 + p * 10 + rand(-0.8, 1));
    const toolWear = Math.round(140 + p * 95 + rand(-8, 12));
    return { airK, procK, rpm, torque, toolWear };
}

function buildPayload({ airK, procK, rpm, torque, toolWear }) {
    const pression = r3(torque / Math.max(rpm, 1));
    const puissance = Math.round(torque * rpm);
    const vibration = r2(rpm / 1000 + rand(0, 0.15));
    const displayC = displayCFromK(airK, procK);
    return {
        machineId: MACHINE_ID,
        air_temperature: r2(airK),
        process_temperature: r2(procK),
        temperature: displayC,
        rpm,
        torque,
        tool_wear: toolWear,
        pressure: pression,
        power: puissance,
        vibration,
        presence: 1,
        magnetic: r2(rand(0.42, 0.62)),
        infrared: r1(procK - 273.15),
        ultrasonic: r1(rand(22, 38)),
    };
}

console.log('\n================================================');
console.log('  DALI PFE — TEST MQTT + IA (unités AI4I / K)');
console.log(`  machineId=${MACHINE_ID}`);
console.log(`  interval = ${SEND_INTERVAL} ms`);
console.log('================================================');
console.log('  Phase 1 : NORMAL (~45–50 °C affichés, proc ~308 K)');
console.log('  Phase 2 : DÉGRADATION (temp process monte)');
console.log('  Phase 3 : PANNE (forte dérive thermique + usure)');
console.log('  → Surviller prob_panne / niveau dans l’app machine Dzli');
console.log('================================================\n');

const client = mqtt.connect(MQTT_BROKER);
let cycleStart = 0;
let currentPhase = -1;
let sendCount = 0;

client.on('connect', () => {
    console.log('MQTT OK\n');
    cycleStart = Date.now();

    setInterval(() => {
        const elapsed = Date.now() - cycleStart;
        let phase;
        let progress;
        let phaseName;
        let phys;

        if (elapsed < PHASE_NORMAL) {
            phase = 0;
            progress = elapsed / PHASE_NORMAL;
            phaseName = 'NORMAL';
            phys = genNormal();
        } else if (elapsed < PHASE_NORMAL + PHASE_DEGRAD) {
            phase = 1;
            progress = (elapsed - PHASE_NORMAL) / PHASE_DEGRAD;
            phaseName = 'DEGRADATION';
            phys = genDegradation(progress);
        } else if (elapsed < TOTAL_CYCLE) {
            phase = 2;
            progress = (elapsed - PHASE_NORMAL - PHASE_DEGRAD) / PHASE_PANNE;
            phaseName = 'PANNE';
            phys = genPanne(progress);
        } else {
            cycleStart = Date.now();
            currentPhase = -1;
            console.log('\n--- Cycle terminé, redémarrage ---\n');
            return;
        }

        if (phase !== currentPhase) {
            currentPhase = phase;
            if (phase === 1) console.log('\n>>> PHASE DÉGRADATION (IA doit monter en risque)\n');
            if (phase === 2) console.log('\n>>> PHASE PANNE (risque élevé attendu)\n');
        }

        const data = buildPayload(phys);
        const json = JSON.stringify(data);
        const topic = `machines/${MACHINE_ID}/telemetry`;
        client.publish(topic, json);
        client.publish('test/machines', json);

        sendCount += 1;
        const min = Math.floor(elapsed / 60000);
        const sec = Math.floor((elapsed % 60000) / 1000);
        const blendK = (phys.airK + phys.procK) / 2;
        console.log(
            `[${String(min).padStart(2, '0')}:${String(sec).padStart(2, '0')}] #${String(sendCount).padStart(3)} ` +
                `${phaseName.padEnd(12)} | T°C=${String(data.temperature).padStart(5)} ` +
                `K≈${r1(blendK)} procK=${r1(phys.procK)} wear=${phys.toolWear} ` +
                `P=${data.power}`,
        );
    }, SEND_INTERVAL);
});

client.on('error', (err) => {
    console.error('MQTT:', err.message);
});
process.on('SIGINT', () => {
    console.log('\nArrêt.');
    client.end();
    process.exit(0);
});
