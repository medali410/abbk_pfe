const mongoose = require('mongoose');
const mongoURI = 'mongodb://127.0.0.1:27017/dali_pfe';

const MachineSchema = new mongoose.Schema({}, { strict: false });
const Machine = mongoose.model('Machine', MachineSchema);

async function run() {
  try {
    await mongoose.connect(mongoURI);
    const machines = await Machine.find({});
    console.log(JSON.stringify(machines.map(m => ({ _id: m._id, name: m.name, companyId: m.companyId })), null, 2));
  } catch (err) {
    console.error(err);
  } finally {
    await mongoose.disconnect();
  }
}
run();
