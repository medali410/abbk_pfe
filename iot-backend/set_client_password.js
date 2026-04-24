const mongoose = require('mongoose');
require('dotenv').config();

const Client = require('./src/models/Client');

async function run() {
  await mongoose.connect(process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/dali_pfe');
  await Client.updateOne(
    { email: 'expresse@dali-pfe.com' },
    { $set: { password: '123456' } }
  );
  console.log('OK client password set to 123456');
  await mongoose.disconnect();
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
