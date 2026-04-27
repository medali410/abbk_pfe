const mongoose = require('mongoose');
const Machine = require('./src/models/Machine');
require('dotenv').config();

async function run() {
  await mongoose.connect(process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe');
  const ids = ['MAC-1775750118162', 'MAC-98B46E90', 'MAC-8BFFD4A6'];
  const machines = await Machine.find({ _id: { $in: ids } });
  machines.forEach(m => console.log(`${m._id}: ${m.name}`));
  mongoose.connection.close();
}
run();
