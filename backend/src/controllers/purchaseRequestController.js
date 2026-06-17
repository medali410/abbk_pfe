const { prisma } = require('../lib/prisma');
const ids = require('../lib/ids');
const { getAuthUserId } = require('../lib/auth');

/**
 * Créer une demande d'achat
 */
async function create(req, res) {
  try {
    const {
      machineId,
      machineName,
      linkedClientId,
      requesterName,
      requesterEmail,
      requesterPhone,
      location,
      googleMapsUrl,
      note,
      requestType,
      requestedSpecialty,
      requestedMachineIds,
    } = req.body;

    if (!machineId || !requesterName) {
      return res.status(400).json({ error: "machineId et requesterName sont obligatoires" });
    }

    const metadataObj = {
      requestedSpecialty: requestedSpecialty || '',
      requestedMachineIds: requestedMachineIds || [],
    };

    const pr = await prisma.purchaseRequest.create({
      data: {
        machineId,
        machineName: machineName || '',
        linkedClientId: linkedClientId || '',
        requesterName,
        requesterEmail: requesterEmail || '',
        requesterPhone: requesterPhone || '',
        location: location || '',
        googleMapsUrl: googleMapsUrl || '',
        note: note || '',
        status: 'PENDING',
        requestType: requestType || 'PURCHASE',
        metadata: JSON.stringify(metadataObj),
      },
    });

    // Auto-assign the machine if linkedClientId is present (Client direct purchase)
    if (linkedClientId) {
      const machine = await prisma.machine.findUnique({ where: { id: machineId } });
      if (machine) {
        const dataToUpdate = { companyId: linkedClientId };
        if (machine.stock > 0) {
          dataToUpdate.stock = machine.stock - 1;
        }
        await prisma.machine.update({
          where: { id: machineId },
          data: dataToUpdate
        });
        
        // Also auto-approve the PR
        await prisma.purchaseRequest.update({
          where: { id: pr.id },
          data: { status: 'APPROVED' }
        });
        pr.status = 'APPROVED';
      }
    }

    let parsedMeta = {};
    try {
      if (pr.metadata && typeof pr.metadata === 'string') {
        parsedMeta = JSON.parse(pr.metadata);
      }
    } catch(e) {}
    
    res.status(201).json({ ...pr, metadata: parsedMeta });
  } catch (error) {
    console.error('Erreur create PurchaseRequest:', error);
    res.status(500).json({ error: "Erreur serveur interne" });
  }
}

/**
 * Lister toutes les demandes d'achat (optionnel filter status)
 */
async function list(req, res) {
  try {
    const { status } = req.query;
    const where = status ? { status } : {};

    const listPr = await prisma.purchaseRequest.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });

    const parsedList = listPr.map(pr => {
      let parsedMeta = {};
      try {
        if (pr.metadata && typeof pr.metadata === 'string') {
          parsedMeta = JSON.parse(pr.metadata);
        }
      } catch(e) {}
      return { ...pr, metadata: parsedMeta };
    });

    res.status(200).json(parsedList);
  } catch (error) {
    console.error('Erreur list PurchaseRequests:', error);
    res.status(500).json({ error: "Erreur serveur interne" });
  }
}

/**
 * Mettre à jour le statut (APPROVED, REJECTED)
 */
async function updateStatus(req, res) {
  try {
    const { id } = req.params;
    const { status, reviewedByName } = req.body;

    const updated = await prisma.purchaseRequest.update({
      where: { id: parseInt(id, 10) },
      data: {
        status: status || 'PENDING',
        reviewedByName: reviewedByName || '',
      },
    });

    res.status(200).json(updated);
  } catch (error) {
    console.error('Erreur updateStatus PurchaseRequest:', error);
    res.status(500).json({ error: "Erreur lors de la mise a jour de la demande" });
  }
}

/**
 * Valider et Provisionner (Client, Tech, Maint, assignation Machine)
 */
async function provisionTeam(req, res) {
  try {
    const { id } = req.params;
    const {
      reviewedByName,
      clientName,
      clientEmail,
      clientPassword,
      clientLocation,
      technicianName,
      technicianPassword,
      technicianLocation,
      maintenanceFirstName,
      maintenanceLastName,
      maintenancePassword,
      maintenanceLocation,
    } = req.body;

    // 1. Get PR
    const pr = await prisma.purchaseRequest.findUnique({
      where: { id: parseInt(id, 10) },
    });
    if (!pr) {
      return res.status(404).json({ error: "Demande d'achat introuvable" });
    }

    // Generate keys
    const tid = ids.nextBusinessId('TECH');
    const mid = ids.nextBusinessId('MAINT');
    const bcrypt = require('bcryptjs');
    const hash = (pwd) => bcrypt.hashSync(pwd || '123456', 10);

    let cid = ids.nextBusinessId('CLI');
    const emailToUse = clientEmail || `client.${cid}@example.com`;
    
    // 2. Client (Create or Find)
    let userClient = await prisma.user.findUnique({
      where: { email: emailToUse },
      include: { client: true }
    });

    if (userClient) {
      if (userClient.client) {
        cid = userClient.client.clientId;
      } else {
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

    // 3. Create Technician
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

    // 4. Create Maintenance
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

    // 5. Update Machine (Assign to client)
    const machine = await prisma.machine.findUnique({
      where: { id: pr.machineId }
    });
    let updatedMachine = null;
    if (machine) {
      const concepteur = await prisma.concepteur.findUnique({ where: { userId: getAuthUserId(req.auth) } });
      const dataToUpdate = { companyId: cid };
      if (concepteur) {
        dataToUpdate.concepteurId = String(concepteur.id);
      }
      if (machine.stock > 0) {
        dataToUpdate.stock = machine.stock - 1;
      }
      
      updatedMachine = await prisma.machine.update({
        where: { id: pr.machineId },
        data: dataToUpdate
      });
    }

    // 6. Update PR status
    await prisma.purchaseRequest.update({
      where: { id: parseInt(id, 10) },
      data: {
        status: 'APPROVED',
        reviewedByName: reviewedByName || 'Concepteur',
      }
    });

    res.status(200).json({
      success: true,
      client: userClient.client,
      technician: userTech.technician,
      maintenanceAgent: userMaint.maintenanceAgent,
      machine: updatedMachine,
    });
  } catch (error) {
    console.error('Erreur provisionTeam:', error);
    res.status(500).json({ error: "Erreur lors du provisionnement" });
  }
}

module.exports = {
  create,
  list,
  updateStatus,
  provisionTeam,
};
