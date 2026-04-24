// Use native fetch (Node.js 18+)
const API_URL = 'http://192.168.100.151:5000/api';

async function simulate() {
    try {
        console.log('Récupération des machines...');
        const res = await fetch(`${API_URL}/machines`);
        if (!res.ok) throw new Error(`Erreur API Machines: ${res.status}`);

        const machines = await res.json();

        if (machines.length === 0) {
            console.log('Aucune machine trouvée pour la simulation.');
            return;
        }

        console.log(`Simulation démarrée pour ${machines.length} machines...`);

        setInterval(async () => {
            for (const machine of machines) {
                // Determine if machine should fail (5% chance)
                const isFailing = Math.random() > 0.95;

                const telemetry = {
                    machineId: machine.id || machine._id,
                    temperature: isFailing ? 86 + Math.random() * 10 : 30 + Math.random() * 40,
                    vibration: isFailing ? 5.1 + Math.random() * 2 : 0.5 + Math.random() * 3,
                    powerConsumption: 5 + Math.random() * 15,
                    proximity: 1,
                    timestamp: new Date().toISOString()
                };

                try {
                    const postRes = await fetch(`${API_URL}/telemetry`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(telemetry)
                    });
                    if (!postRes.ok) console.error(`Erreur POST pour ${machine.name}: ${postRes.status}`);
                } catch (err) {
                    console.error(`Erreur réseau pour ${machine.name}:`, err.message);
                }
            }
        }, 3000);

    } catch (error) {
        console.error('Erreur lors du démarrage de la simulation:', error.message);
    }
}

simulate();
