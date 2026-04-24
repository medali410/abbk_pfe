/**
 * Simulateur de scénarios de panne - VERSION NODE.JS
 * 
 * Envoie des données via MQTT exactement comme le ferait un ESP32.
 * Cycle: 5min NORMAL -> 5min PANNE (6 types) en boucle.
 *
 * Usage:
 *   node simulate_scenarios.js MAC-XXXXXX
 *   (remplacer MAC-XXXXXX par l'ID de la machine à simuler)
 */

const mqtt = require('mqtt');

const MACHINE_ID = process.argv[2] || '';
/** EL_S | EL_M | EL_L — aligné encodeur IA (ne pas utiliser de texte libre). */
const MOTOR_TYPE = 'EL_M';
const MQTT_BROKER = 'mqtt://broker.hivemq.com';
const SCENARIO_DURATION = 5 * 60 * 1000; // 5 minutes
const SEND_INTERVAL = 3000;              // 3 secondes

if (!MACHINE_ID) {
    console.error('\n  Usage: node simulate_scenarios.js <MACHINE_ID>');
    console.error('  Exemple: node simulate_scenarios.js MAC-00A1\n');
    process.exit(1);
}

const SCENARIOS = [
    'NORMAL', 'SURCHAUFFE',
    'NORMAL', 'ROULEMENT',
    'NORMAL', 'SURCHARGE',
    'NORMAL', 'ELECTRIQUE',
    'NORMAL', 'USURE_GENERALE',
    'NORMAL', 'PRESSION',
];

function rand(min, max) {
    return min + Math.random() * (max - min);
}

function generateNormal() {
    const t = rand(35, 55);
    return {
        temperature: t, pression: rand(0.02, 0.04), puissance: rand(50000, 70000),
        vibration: rand(0.5, 1.5), presence: 1, magnetique: rand(0.4, 0.7),
        infrarouge: t + rand(-3, 5), ultrasonic: rand(20, 60),
    };
}

function generateSurchauffe(p) {
    const t = 60 + p * 60 + rand(-3, 3) + (p > 0.3 ? Math.sin(p * 20) * 8 : 0);
    return {
        temperature: t, pression: rand(0.03, 0.06), puissance: rand(80000, 130000),
        vibration: 1.5 + p * 2 + rand(-0.3, 0.3), presence: 1, magnetique: rand(0.5, 0.8),
        infrarouge: t + rand(5, 20), ultrasonic: rand(20, 60),
    };
}

function generateRoulement(p) {
    let vib = 3 + p * 5 + rand(-0.5, 0.5);
    if (Math.random() < 0.3) vib += rand(2, 4);
    const t = 50 + p * 25 + rand(-2, 2);
    return {
        temperature: t, pression: rand(0.02, 0.04), puissance: rand(55000, 85000),
        vibration: vib, presence: 1, magnetique: rand(0.3, 0.7),
        infrarouge: t + rand(0, 8), ultrasonic: rand(15, 70),
    };
}

function generateSurcharge(p) {
    const t = 55 + p * 30 + rand(-2, 2);
    return {
        temperature: t, pression: 0.05 + p * 0.08 + rand(-0.01, 0.01),
        puissance: 120000 + p * 80000 + rand(-5000, 5000),
        vibration: 2 + p * 2.5 + rand(-0.3, 0.3), presence: 1,
        magnetique: rand(0.6, 0.95), infrarouge: t + rand(3, 10),
        ultrasonic: rand(20, 60),
    };
}

function generateElectrique(p) {
    const t = 45 + p * 40 + rand(-5, 5);
    const puiss = Math.random() < 0.4 ? rand(10000, 30000) : rand(100000, 170000);
    return {
        temperature: t, pression: rand(0.01, 0.03), puissance: puiss,
        vibration: rand(1, 3), presence: Math.random() < 0.2 ? 0 : 1,
        magnetique: Math.random() < 0.5 ? rand(0.05, 0.15) : rand(0.85, 0.98),
        infrarouge: t + rand(-10, 20), ultrasonic: rand(20, 60),
    };
}

function generateUsure(p) {
    const t = 50 + p * 20 + rand(-3, 3);
    return {
        temperature: t, pression: 0.03 + p * 0.04 + rand(-0.005, 0.005),
        puissance: 60000 - p * 20000 + rand(-3000, 3000),
        vibration: 2 + p * 3.5 + rand(-0.5, 0.5), presence: 1,
        magnetique: 0.5 - p * 0.3 + rand(-0.05, 0.05),
        infrarouge: t + rand(0, 10), ultrasonic: rand(20, 60),
    };
}

function generatePression(p) {
    const t = 55 + p * 15 + rand(-2, 2);
    let pres = 0.04 + Math.sin(p * 15) * 0.05 + rand(-0.01, 0.01);
    if (pres < 0.005) pres = 0.005;
    return {
        temperature: t, pression: pres, puissance: rand(60000, 90000),
        vibration: 1.5 + p * 1.5 + rand(-0.3, 0.3), presence: 1,
        magnetique: rand(0.4, 0.7), infrarouge: t + rand(0, 5),
        ultrasonic: rand(20, 60),
    };
}

const generators = {
    NORMAL: () => generateNormal(),
    SURCHAUFFE: (p) => generateSurchauffe(p),
    ROULEMENT: (p) => generateRoulement(p),
    SURCHARGE: (p) => generateSurcharge(p),
    ELECTRIQUE: (p) => generateElectrique(p),
    USURE_GENERALE: (p) => generateUsure(p),
    PRESSION: (p) => generatePression(p),
};

console.log('\n==========================================');
console.log('  DALI PFE - SIMULATEUR DE PANNES');
console.log(`  Machine: ${MACHINE_ID}`);
console.log('==========================================');
console.log('  Cycle: 5min Normal -> 5min Panne');
console.log('  6 types: Surchauffe, Roulement,');
console.log('  Surcharge, Electrique, Usure, Pression');
console.log('==========================================\n');

const client = mqtt.connect(MQTT_BROKER);
let phase = 0;
let phaseStart = Date.now();

client.on('connect', () => {
    console.log('MQTT connecte!\n');
    printPhase();

    setInterval(() => {
        const now = Date.now();
        if (now - phaseStart >= SCENARIO_DURATION) {
            phaseStart = now;
            phase = (phase + 1) % SCENARIOS.length;
            console.log('');
            printPhase();
        }

        const progress = (now - phaseStart) / SCENARIO_DURATION;
        const scenario = SCENARIOS[phase];
        const gen = generators[scenario];
        const data = gen ? gen(progress) : generateNormal();

        const payload = {
            machineId: MACHINE_ID,
            type_moteur: MOTOR_TYPE,
            temperature: Math.round(data.temperature * 10) / 10,
            pressure: Math.round(data.pression * 1000) / 1000,
            power: Math.round(data.puissance),
            vibration: Math.round(data.vibration * 100) / 100,
            presence: data.presence,
            magnetic: Math.round(data.magnetique * 100) / 100,
            infrared: Math.round(data.infrarouge * 10) / 10,
            ultrasonic: Math.round(data.ultrasonic * 10) / 10,
            rpm: 1500,
            torque: 40,
        };

        const topic = `machines/${MACHINE_ID}/telemetry`;
        client.publish(topic, JSON.stringify(payload));
        client.publish('test/machines', JSON.stringify(payload));

        const remaining = Math.ceil((SCENARIO_DURATION - (now - phaseStart)) / 1000);
        const bar = scenario === 'NORMAL' ? '\x1b[32m■\x1b[0m' : '\x1b[31m■\x1b[0m';
        process.stdout.write(
            `\r  ${bar} [${scenario.padEnd(16)}] T=${payload.temperature.toFixed(1)}°C ` +
            `V=${payload.vibration.toFixed(1)} P=${payload.power} ` +
            `Mag=${payload.magnetic.toFixed(2)} | ${remaining}s restant  `
        );
    }, SEND_INTERVAL);
});

function printPhase() {
    const scenario = SCENARIOS[phase];
    const isFailure = scenario !== 'NORMAL';
    const color = isFailure ? '\x1b[31m' : '\x1b[32m';
    console.log(`${color}========================================`);
    console.log(`  PHASE ${phase + 1}/${SCENARIOS.length}: ${scenario}`);
    console.log(`========================================\x1b[0m`);
}

client.on('error', (err) => console.error('MQTT erreur:', err.message));
