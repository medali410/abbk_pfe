const DashboardModel = require('../models/dashboardModel');

async function kpis(req, res) {
    try {
        res.set('Cache-Control', 'no-store');
        return res.json(await DashboardModel.getKpis());
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function fleetOverview(req, res) {
    try {
        res.set('Cache-Control', 'no-store');
        return res.json(await DashboardModel.getFleetOverview());
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = { kpis, fleetOverview };
