const mongoose = require('mongoose');
const mongoURI = 'mongodb://127.0.0.1:27017/dali_pfe';

const TechnicianSchema = new mongoose.Schema({}, { strict: false });
const Technician = mongoose.model('Technician', TechnicianSchema);

async function run() {
  try {
    await mongoose.connect(mongoURI);
    const techs = await Technician.find({});
    console.log(JSON.stringify(techs.map(t => ({ _id: t._id, name: t.name, machineIds: t.machineIds })), null, 2));
  } catch (err) {
    console.error(err);
  } finally {
    await mongoose.disconnect();
  }
}
run();
