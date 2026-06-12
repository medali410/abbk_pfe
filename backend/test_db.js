require('dotenv').config();
const http = require('http');

const jwt = require('./src/lib/jwtToken');
const token = jwt.signToken({ id: 1, email: 'admin@admin.com', role: 'superadmin', nom: 'Admin' });

const options = {
  hostname: 'localhost',
  port: 3001,
  path: '/api/maintenance-agents',
  method: 'GET',
  headers: {
    'Authorization': 'Bearer ' + token
  }
};

const req = http.request(options, res => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => console.log('Response:', res.statusCode, data));
});

req.on('error', error => console.error(error));
req.end();
