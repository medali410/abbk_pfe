const API_URL = 'http://127.0.0.1:3001/api';

async function simulate() {
    try {
        console.log('🔍 Récupération des machines...');
        const res = await fetch(`${API_URL}/machines`);
        const data = await res.json();

        const machines = Array.isArray(data) ? data : [];

        if (machines.length === 0) {
            console.log('❌ Aucune machine trouvée ou erreur API:', data);
            return;
        }

        console.log(`🚀 Simulation démarrée pour ${machines.length} machines...`);

        setInterval(async () => {
            for (const machine of machines) {
                const machineId = machine.id || machine._id;

                // Generate metrics for all 7 keys
                const metrics = {
                    thermal: 40 + Math.random() * 30,
                    pressure: 1 + Math.random() * 4,
                    power: 10 + Math.random() * 40,
                    ultrasonic: 30 + Math.random() * 70,
                    presence: Math.random() > 0.5 ? 1 : 0,
                    magnetic: Math.random() * 100,
                    infrared: 20 + Math.random() * 60,
                };

                const telemetry = {
                    machineId: machineId,
                    temperature: metrics.thermal,
                    powerConsumption: metrics.power / 2.5,
                    metrics: metrics,
                    timestamp: new Date().toISOString()
                };

                try {
                    const postRes = await fetch(`${API_URL}/telemetry`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(telemetry)
                    });
                    if (!postRes.ok) {
                        const errText = await postRes.text();
                        console.error(`❌ Erreur POST pour ${machine.name || machineId}: ${postRes.status}`, errText);
                    }
                } catch (err) {
                    console.error(`❌ Erreur réseau pour ${machine.name || machineId}:`, err.message);
                }
            }
        }, 3000);

    } catch (error) {
        console.error('❌ Erreur:', error.message);
    }
}

simulate();
