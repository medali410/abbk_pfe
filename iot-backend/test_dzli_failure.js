const API_URL = 'http://localhost:3001/api';

async function forceDzliFailure() {
    const machineId = 'MAC-1775750118162';
    console.log(`Forçage de la panne pour la machine dzli (${machineId})...`);

    // Scénario de panne critique : Température et Vibration très élevées
    const telemetry = {
        machineId: machineId,
        temperature: 95.0,    
        vibration: 82.0,      
        powerConsumption: 5500,
        pressure: 6.5,
        timestamp: new Date().toISOString()
    };

    try {
        const postRes = await fetch(`${API_URL}/telemetry`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(telemetry)
        });

        if (postRes.ok) {
            const result = await postRes.json();
            console.log('--- TEST RÉUSSI ---');
            console.log('Machine "dzli" est maintenant en état de PANNE CRITIQUE.');
            console.log('Probabilité de panne calculée:', result.prob_panne || 'Calculée par le backend');
            console.log('\nÉTAPES POUR LE TEST :');
            console.log('1. Ouvrez le dashboard Maintenance.');
            console.log('2. Cherchez la machine "dzli" (elle doit être ROUGE).');
            console.log('3. Cliquez sur la machine pour ouvrir les détails.');
            console.log('4. À droite, vous verrez le panneau "ÉQUIPE DE CONTRÔLE".');
            console.log('5. Sélectionnez un technicien et validez.');
        } else {
            const err = await postRes.text();
            console.error('Erreur lors de l\'envoi:', postRes.status, err);
        }
    } catch (error) {
        console.error('Erreur:', error.message);
    }
}

forceDzliFailure();
