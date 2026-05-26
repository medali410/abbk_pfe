const { prisma } = require('../lib/prisma');

async function check(req, res) {
    try {
        const [users, clients, machines, documents] = await Promise.all([
            prisma.user.count(),
            prisma.client.count(),
            prisma.machine.count(),
            prisma.document.count(),
        ]);
        const port = parseInt(String(process.env.PORT || '3001'), 10);
        res.json({
            ok: true,
            service: 'dali-pfe-backend/sql',
            architecture: 'mvc',
            port,
            mongo: 'n/a',
            mongoMode: 'sql',
            dataSource: 'prisma-sql',
            machineCount: machines,
            counts: { users, clients, machines, documents },
            api: {
                login: 'POST /api/login',
                clients: 'GET /api/clients',
                machines: 'GET /api/machines?catalog=1',
                documents: 'GET /api/conceptions',
                kpis: 'GET /api/dashboard/kpis',
            },
        });
    } catch (err) {
        res.status(503).json({ ok: false, error: err.message });
    }
}

module.exports = { check };
