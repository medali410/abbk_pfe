const http = require('http');

const testCases = [
    { method: 'POST', path: '/api/chat/messages', body: { roomId: 'test_123', from: 'technician', senderName: 'Dali', text: 'Hello', userId: 1 } },
    { method: 'GET', path: '/api/chat/messages/test_123' },
    { method: 'GET', path: '/api/chat/conversations/conception' },
    { method: 'GET', path: '/api/chat/conversations/role/technician' },
    { method: 'GET', path: '/api/chat/room/test_123/participants' }
];

async function runTests() {
    console.log('Starting tests...');
    for (const t of testCases) {
        await new Promise((resolve) => {
            const options = {
                hostname: 'localhost',
                port: 3001,
                path: t.path,
                method: t.method,
                headers: t.body ? { 'Content-Type': 'application/json' } : {}
            };

            const req = http.request(options, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    console.log(`[${t.method}] ${t.path} -> ${res.statusCode}`);
                    if (res.statusCode !== 200 && res.statusCode !== 201) {
                        console.error(data.slice(0, 200));
                    }
                    resolve();
                });
            });

            req.on('error', (e) => {
                console.error(`Error on ${t.path}:`, e.message);
                resolve();
            });

            if (t.body) {
                req.write(JSON.stringify(t.body));
            }
            req.end();
        });
    }
}

runTests();
