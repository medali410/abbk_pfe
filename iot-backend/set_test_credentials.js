const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const Client = require('./src/models/Client');
const Technician = require('./src/models/Technician');

async function run() {
  await mongoose.connect(process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe');
  const clientEmail = 'expresse@dali-pfe.com';
  const techEmail = 'ena@gmail.com';
  const password = 'Test@123';

  await Client.updateOne({ email: clientEmail.toLowerCase() }, { $set: { password } });
  await Technician.updateOne(
    { email: techEmail.toLowerCase() },
    { $set: { password: await bcrypt.hash(password, 10) } }
  );

  console.log('UPDATED', { clientEmail, techEmail, password });
  await mongoose.disconnect();
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
