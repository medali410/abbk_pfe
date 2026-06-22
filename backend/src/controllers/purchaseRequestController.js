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
    // REMOVED: Now we want the concepteur to validate the purchase request manually
    // even if it comes from an existing client.


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

    // 3. Obtenir le Concepteur et Assignation Machine au Client
    const concepteur = await prisma.concepteur.findUnique({ where: { userId: getAuthUserId(req.auth) } });
    
    const machine = await prisma.machine.findUnique({
      where: { id: pr.machineId }
    });
    
    let updatedMachine = null;
    if (machine) {
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

    // 4. Mettre à jour les Techniciens et Agents du Concepteur
    // On ajoute la machine à leurs droits
    if (concepteur && concepteur.companyId) {
      const cId = concepteur.companyId;

      // Techniciens
      const techs = await prisma.technician.findMany({ where: { companyId: cId } });
      for (const t of techs) {
        let mIds = [];
        try { mIds = JSON.parse(t.machineIds || '[]'); } catch(e) {}
        if (!mIds.includes(pr.machineId)) {
          mIds.push(pr.machineId);
          await prisma.technician.update({
            where: { id: t.id },
            data: { machineIds: JSON.stringify(mIds) }
          });
        }
      }

      // Agents de maintenance
      const agents = await prisma.maintenanceAgent.findMany({ where: { clientId: cId } });
      for (const a of agents) {
        let mIds = [];
        try { mIds = JSON.parse(a.machineIds || '[]'); } catch(e) {}
        if (!mIds.includes(pr.machineId)) {
          mIds.push(pr.machineId);
          await prisma.maintenanceAgent.update({
            where: { id: a.id },
            data: { machineIds: JSON.stringify(mIds) }
          });
        }
      }
    }

    // 5. Update PR status
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
