require('dotenv').config();
const { prisma } = require('./src/lib/prisma');

async function main() {
  try {
    const machineCount = await prisma.machine.count();
    const telemetryCount = await prisma.telemetry.count();
    const predictionCount = await prisma.prediction.count();
    const userCount = await prisma.user.count();

    console.log('Database Counts:');
    console.log('- Users:', userCount);
    console.log('- Machines:', machineCount);
    console.log('- Telemetries:', telemetryCount);
    console.log('- Predictions:', predictionCount);

    const latestTelemetry = await prisma.telemetry.findFirst({
      orderBy: { timestamp: 'desc' }
    });
    console.log('\nLatest Telemetry:', latestTelemetry);

    const latestPrediction = await prisma.prediction.findFirst({
      orderBy: { createdAt: 'desc' }
    });
    console.log('\nLatest Prediction:', latestPrediction);

    const sampleMachines = await prisma.machine.findMany({
      take: 5
    });
    console.log('\nSample Machines Statuses:', sampleMachines.map(m => ({ id: m.id, name: m.name, status: m.status, location: m.location })));

  } catch (e) {
    console.error('Error querying DB:', e);
  } finally {
    await prisma.$disconnect();
  }
}

main();
