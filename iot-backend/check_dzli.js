const mongoose = require('mongoose');
const mongoURI = 'mongodb://127.0.0.1:27017/dali_pfe';

const MachineSchema = new mongoose.Schema({
  _id: { type: String, required: true }
}, { strict: false });
const Machine = mongoose.model('Machine', MachineSchema);

async function run() {
  try {
    await mongoose.connect(mongoURI);
    const m = await Machine.findOne({ _id: "MAC-1775750118162" }).lean();
    console.log(JSON.stringify(m, null, 2));
  } catch (err) {
    console.error(err);
  } finally {
    await mongoose.disconnect();
  }
}
run();
