const mongoose = require('mongoose');
const Machine = require('./src/models/Machine');
require('dotenv').config();

mongoose.connect(process.env.MONGODB_URI)
    .then(async () => {
        const machine = await Machine.findOne({ name: 'Compresseur B2' });
        if (machine) {
            console.log(`FOUND_MACHINE_ID: ${machine._id}`);
            console.log(`CURRENT_STATUS: ${machine.status}`);
        } else {
            console.log('Machine not found');
        }
        process.exit();
    })
    .catch(err => {
        console.error(err);
        process.exit(1);
    });
