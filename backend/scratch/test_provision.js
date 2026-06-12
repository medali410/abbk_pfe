const { prisma } = require('../src/lib/prisma');
const ids = require('../src/lib/ids');

async function test() {
  const id = 10;
  const clientEmail = "fathi@gmail.com";
  const clientName = "fa foead";
  const clientPassword = "clientpassword";
  const clientLocation = "nabeul";
  const technicianName = "Technicien Terrain";
  const technicianPassword = "tech123";
  const technicianLocation = "nabeul";
  const maintenanceFirstName = "Maintenance";
  const maintenanceLastName = "Agent";
  const maintenancePassword = "maint123";
  const maintenanceLocation = "nabeul";

  console.log('Testing provisionTeam...');

  // 1. Get PR
  const pr = await prisma.purchaseRequest.findUnique({
    where: { id: parseInt(id, 10) },
  });
  if (!pr) {
    console.error("Demande d'achat introuvable");
    return;
  }

  // Generate keys
  const tid = ids.nextBusinessId('TECH');
  const mid = ids.nextBusinessId('MAINT');
  const bcrypt = require('bcryptjs');
  const hash = (pwd) => bcrypt.hashSync(pwd || '123456', 10);

  let cid = ids.nextBusinessId('CLI');
  const emailToUse = clientEmail || `client.${cid}@example.com`;
  
  try {
    // 2. Client (Create or Find)
    let userClient = await prisma.user.findUnique({
      where: { email: emailToUse },
      include: { client: true }
    });

    if (userClient) {
      if (userClient.client) {
        cid = userClient.client.clientId;
      } else {
        console.log('Client user exists but profile missing. Creating profile...');
        const newClient = await prisma.client.create({
          data: {
            userId: userClient.id,
            clientId: cid,
            location: clientLocation || pr.location || '',
          }
        });
        userClient.client = newClient;
      }
    } else {
      console.log('Creating new Client user...');
      userClient = await prisma.user.create({
        data: {
          email: emailToUse,
          password: hash(clientPassword),
          nom: clientName || pr.requesterName || 'Client',
          role: 'client',
          client: {
            create: {
              clientId: cid,
              location: clientLocation || pr.location || '',
            }
          }
        },
        include: { client: true }
      });
    }
    console.log('Client step OK, cid:', cid);

    // 3. Create Technician
    console.log('Creating Technician...');
    const userTech = await prisma.user.create({
      data: {
        email: `tech.${tid}@example.com`,
        password: hash(technicianPassword),
        nom: technicianName || 'Technicien',
        role: 'technician',
        technician: {
          create: {
            technicianId: tid,
            companyId: cid,
            firstName: technicianName || 'Technicien',
            machineIds: JSON.stringify([pr.machineId]),
          }
        }
      },
      include: { technician: true }
    });
    console.log('Technician created OK, email:', userTech.email);

    // 4. Create Maintenance
    console.log('Creating Maintenance...');
    const userMaint = await prisma.user.create({
      data: {
        email: `maint.${mid}@example.com`,
        password: hash(maintenancePassword),
        nom: `${maintenanceFirstName} ${maintenanceLastName}`,
        role: 'maintenance',
        maintenanceAgent: {
          create: {
            maintenanceAgentId: mid,
            clientId: cid,
            firstName: maintenanceFirstName || 'Maintenance',
            lastName: maintenanceLastName || '',
            machineIds: JSON.stringify([pr.machineId]),
          }
        }
      },
      include: { maintenanceAgent: true }
    });
    console.log('Maintenance created OK, email:', userMaint.email);

    // 5. Update Machine (Assign to client)
    console.log('Updating Machine...');
    const machine = await prisma.machine.findUnique({
      where: { id: pr.machineId }
    });
    let updatedMachine = null;
    if (machine) {
      const concepteurId = "5"; // mock concepteur ID
      const dataToUpdate = { companyId: cid, concepteurId };
      
      updatedMachine = await prisma.machine.update({
        where: { id: pr.machineId },
        data: dataToUpdate
      });
    }
    console.log('Machine updated OK');

  } catch (error) {
    console.error('CRASH IN PROVISIONING:', error);
  }
}

test();
