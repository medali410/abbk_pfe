require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  try {
    const machineId = "MAC-TEST-VERIN";
    const name = "Vérin Hydraulique de Test";
    
    // Upsert the test machine
    const machine = await prisma.machine.upsert({
      where: { id: machineId },
      update: {
        name: name,
        type: "Vérin",
        companyId: "CLI-A81DF6", // Client "morad mm"
        concepteurId: "5",        // Concepteur "lemjid hammaaaaa"
        status: "RUNNING",
      },
      create: {
        id: machineId,
        name: name,
        type: "Vérin",
        companyId: "CLI-A81DF6", // Client "morad mm"
        concepteurId: "5",        // Concepteur "lemjid hammaaaaa"
        status: "RUNNING",
      }
    });

    console.log("SUCCESS: Created test machine:", JSON.stringify(machine, null, 2));
  } catch (err) {
    console.error("ERROR creating test machine:", err);
  } finally {
    await prisma.$disconnect();
  }
}

main();
