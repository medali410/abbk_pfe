const API_URL = 'http://localhost:5000/api';
// Replace with actual ID after running get_machine_api.js
const MACHINE_ID = process.argv[2];

if (!MACHINE_ID) {
    console.error('Please provide machine ID');
    process.exit(1);
}

async function simulateBreakdown() {
    const telemetry = {
        machineId: MACHINE_ID,
        temperature: 120, // High temperature > 90
        vibration: 80,    // High vibration > 70
        powerConsumption: 110, // High power > 100
        timestamp: new Date().toISOString()
    };

    try {
        const res = await fetch(`${API_URL}/telemetry`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(telemetry)
        });

        if (res.ok) {
            const data = await res.json();
            console.log('Telemetry sent successfully');
            console.log('Alerts created:', data.alerts);
        } else {
            console.error(`Error: ${res.status}`);
        }
    } catch (error) {
        console.error(error.message);
    }
}

simulateBreakdown();
