/** @deprecated Préférer `../views/userView` et `../views/machineView` (architecture MVC). */
const userView = require('../views/userView');
const machineView = require('../views/machineView');

module.exports = {
    ...userView,
    ...machineView,
};
