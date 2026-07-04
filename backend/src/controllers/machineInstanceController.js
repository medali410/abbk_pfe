// src/controllers/machineInstanceController.js
// Gestion des instances physiques individuelles de chaque machine
const { prisma } = require('../lib/prisma');
const mqtt = require('../lib/mqtt');

/**
 * Sérialise une instance pour l'API
 */
function serializeInstance(inst) {
  return {
    id: inst.id,
    instanceId: inst.id,
    modelId: inst.modelId,
    modelName: inst.model?.name || '',
    ipAddress: inst.ipAddress,
    clientId: inst.clientId,
    concepteurId: inst.concepteurId,
    status: inst.status,
    mqttTopic: `machines/${inst.id}/telemetry`,
    mqttTopicControl: `machines/${inst.id}/control`,
    wifiSsid: inst.wifiSsid,
    isAssigned: !!inst.clientId,
    purchasedAt: inst.purchasedAt,
    activatedAt: inst.activatedAt,
    createdAt: inst.createdAt,
    updatedAt: inst.updatedAt,
    // Modèle parent enrichi
    model: inst.model ? {
      id: inst.model.id,
      name: inst.model.name,
      type: inst.model.type,
      motorType: inst.model.motorType,
      imageUrl: inst.model.imageUrl,
      aiType: inst.model.aiType,
    } : null,
  };
}

/**
 * GET /api/machine-instances
 * Lister les instances — filtres optionnels: clientId, modelId, concepteurId, available=1
 */
async function listInstances(req, res) {
  try {
    const { clientId, modelId, concepteurId, available } = req.query;
    const where = {};
    if (clientId)     where.clientId     = String(clientId);
    if (modelId)      where.modelId      = String(modelId);
    if (concepteurId) where.concepteurId = String(concepteurId);
    if (available === '1') where.clientId = ''; // non assignées

    const instances = await prisma.machineInstance.findMany({
      where,
      include: { model: true },
      orderBy: { id: 'asc' },
    });

    res.set('Cache-Control', 'no-store');
    return res.json(instances.map(serializeInstance));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

/**
 * GET /api/machine-instances/:instanceId
 * Détail d'une instance
 */
async function getInstance(req, res) {
  try {
    const inst = await prisma.machineInstance.findUnique({
      where: { id: req.params.instanceId },
      include: { model: true },
    });
    if (!inst) return res.status(404).json({ error: 'Instance introuvable' });
    return res.json(serializeInstance(inst));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

/**
 * GET /api/machines/:machineId/instances
 * Lister toutes les instances d'un modèle
 */
async function listInstancesByModel(req, res) {
  try {
    const instances = await prisma.machineInstance.findMany({
      where: { modelId: req.params.machineId },
      include: { model: true },
      orderBy: { id: 'asc' },
    });
    return res.json(instances.map(serializeInstance));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

/**
 * PATCH /api/machine-instances/:instanceId/status
 * Changer le statut d'une instance (RUNNING, STOPPED, STOPPED_DANGER)
 */
async function updateInstanceStatus(req, res) {
  try {
    const { instanceId } = req.params;
    const { status } = req.body;
    if (!status) return res.status(400).json({ error: 'status est requis' });

    const inst = await prisma.machineInstance.update({
      where: { id: instanceId },
      data: { status: String(status) },
      include: { model: true },
    });

    // Publier la commande MQTT sur le topic de l'instance
    const command = status === 'RUNNING' ? 'ON' : 'OFF';
    mqtt.publish(`machines/${instanceId}/control`, JSON.stringify({ command }));

    return res.json(serializeInstance(inst));
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

/**
 * PATCH /api/machine-instances/:instanceId/config
 * Configurer WiFi + ID d'une instance (publie sur MQTT)
 */
async function configInstance(req, res) {
  try {
    const { instanceId } = req.params;
    const { ssid, password } = req.body;
    if (!ssid || !password) return res.status(400).json({ error: 'ssid et password obligatoires' });

    const inst = await prisma.machineInstance.update({
      where: { id: instanceId },
      data: { wifiSsid: ssid, wifiPassword: password },
      include: { model: true },
    });

    // Publier la config sur le topic MQTT de l'instance
    mqtt.publish(`machines/${instanceId}/config`, JSON.stringify({
      ssid,
      password,
      machineId: instanceId,
    }));

    return res.json({ success: true, instance: serializeInstance(inst) });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

/**
 * POST /api/machine-instances/bulk-create
 * Créer manuellement des instances pour un modèle existant (si stock augmenté)
 */
async function bulkCreateInstances(req, res) {
  try {
    const { modelId, quantity, baseIp } = req.body;
    if (!modelId || !quantity) return res.status(400).json({ error: 'modelId et quantity requis' });

    const machine = await prisma.machine.findUnique({ where: { id: modelId } });
    if (!machine) return res.status(404).json({ error: 'Modèle de machine introuvable' });

    // Trouver le dernier numéro d'instance existant
    const existing = await prisma.machineInstance.findMany({
      where: { modelId },
      orderBy: { id: 'desc' },
    });
    const lastNum = existing.length > 0
      ? parseInt(existing[0].id.split('-').pop(), 10) || existing.length
      : 0;

    const ipPrefix = baseIp || machine.baseIp || '192.168.1';
    const created = [];
    for (let i = 1; i <= quantity; i++) {
      const num = lastNum + i;
      const instanceId = `${modelId}-${String(num).padStart(3, '0')}`;
      const ipSuffix = 100 + num;
      created.push({
        id: instanceId,
        modelId,
        ipAddress: `${ipPrefix}.${ipSuffix}`,
        concepteurId: machine.concepteurId || '',
        status: 'STOPPED',
      });
    }

    await prisma.machineInstance.createMany({ data: created, skipDuplicates: true });

    // Mettre à jour le stock
    await prisma.machine.update({
      where: { id: modelId },
      data: { stock: { increment: quantity } },
    });

    const all = await prisma.machineInstance.findMany({
      where: { modelId },
      include: { model: true },
      orderBy: { id: 'asc' },
    });
    return res.status(201).json({ created: created.length, instances: all.map(serializeInstance) });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

module.exports = {
  listInstances,
  getInstance,
  listInstancesByModel,
  updateInstanceStatus,
  configInstance,
  bulkCreateInstances,
};
