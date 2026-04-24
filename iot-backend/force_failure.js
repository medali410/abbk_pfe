const API_URL = 'http://localhost:5000/api';

async function forceFailure() {
    try {
        console.log('Récupération de la machine "Ligne Production A"...');
        const res = await fetch(`${API_URL}/machines`);
        if (!res.ok) throw new Error(`Erreur API Machines: ${res.status}`);

        const machines = await res.json();
        const machine = machines.find(m => m.name === 'Ligne Production A');

        if (!machine) {
            console.log('Machine "Ligne Production A" non trouvée.');
            return;
        }

        const machineId = machine.id || machine._id;
        console.log(`Machine trouvée! ID: ${machineId}`);

        // Scénario de panne : Température et Vibration très élevées
        const telemetry = {
            machineId: machineId,
            temperature: 98.5,    // Seuil high: 90 (Backend), UI: 85
            vibration: 85.0,      // Seuil high: 70 (Backend), UI: 5
            powerConsumption: 92, // Seuil medium: 80 (Backend)
            proximity: 1,
            timestamp: new Date().toISOString()
        };

        console.log('Envoi des données de panne...');
        const postRes = await fetch(`${API_URL}/telemetry`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(telemetry)
        });

        if (postRes.ok) {
            const result = await postRes.json();
            console.log('Panne simulée avec succès !');
            console.log('Alertes générées:', result.alerts ? result.alerts.length : 0);
            if (result.alerts) {
                result.alerts.forEach(a => console.log(` - ${a.message}`));
            }
            console.log('\nConsultez l\'application web pour voir le résultat.');
        } else {
            console.error('Erreur lors de l\'envoi de la télémétrie:', postRes.status);
        }

    } catch (error) {
        console.error('Erreur:', error.message);
    }
}

forceFailure();
