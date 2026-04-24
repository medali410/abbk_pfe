const mongoose = require('mongoose');
const mongoURI = 'mongodb://127.0.0.1:27017/dali_pfe';

const TechnicianSchema = new mongoose.Schema({}, { strict: false });
const Technician = mongoose.model('Technician', TechnicianSchema);

async function run() {
  try {
    await mongoose.connect(mongoURI);
    const techs = await Technician.find({}).lean();
    console.log(JSON.stringify(techs, null, 2));
  } catch (err) {
    console.error(err);
  } finally {
    await mongoose.disconnect();
  }
}
run();
