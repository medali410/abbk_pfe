const crypto = require('crypto');

function nextBusinessId(prefix) {
    const hex = crypto.randomBytes(3).toString('hex').toUpperCase();
    return `${prefix}-${hex}`;
}

function nextMachineId() {
    const hex = crypto.randomBytes(4).toString('hex').toUpperCase();
    return `MAC-${hex}`;
}

module.exports = { nextBusinessId, nextMachineId };
