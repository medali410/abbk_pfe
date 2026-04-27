const axios = require('axios');

async function checkApi() {
    try {
        const response = await axios.get('http://127.0.0.1:3001/api/machines');
        console.log(JSON.stringify(response.data, null, 2));
    } catch (error) {
        console.error('Error fetching machines:', error.message);
    }
}

checkApi();
