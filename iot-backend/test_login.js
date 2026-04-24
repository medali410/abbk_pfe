const axios = require('axios');
axios.post('http://localhost:5000/api/auth/login', {username: 'company', password: 'password123'})
  .then(r => console.log('SUCCESS:', r.data))
  .catch(e => console.error('ERROR:', e.response ? e.response.data : e.message));
