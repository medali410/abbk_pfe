const API_URL = 'http://localhost:5000/api';

async function getMachines() {
    try {
        const res = await fetch(`${API_URL}/machines`);
        const machines = await res.json();
        const machine = machines.find(m => m.name === 'Compresseur B2');
        if (machine) {
            console.log(`ID: ${machine.id || machine._id}`);
            console.log(`Name: ${machine.name}`);
        } else {
            console.log('Not found');
        }
    } catch (error) {
        console.error(error.message);
    }
}

getMachines();
