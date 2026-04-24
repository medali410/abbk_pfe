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
    console.log("Machine ID:", m._id);
    console.log("Company ID:", m.companyId);
    console.log("Client ID:", m.clientId);
    console.log("Keys:", Object.keys(m));
  } catch (err) {
    console.error(err);
  } finally {
    await mongoose.disconnect();
  }
}
run();
