/** @deprecated Préférer `../models/dashboardModel` (architecture MVC). */
const DashboardModel = require('../models/dashboardModel');

module.exports = {
    getDashboardKpis: DashboardModel.getKpis,
    getFleetOverview: DashboardModel.getFleetOverview,
    isRunning: () => {},
    riskPctForMachine: () => {},
};
