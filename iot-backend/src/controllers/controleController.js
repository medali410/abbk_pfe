const mongoose = require('mongoose');
const Controle = require('../models/Controle');
const Machine = require('../models/Machine');
const Technician = require('../models/Technician');
const { PREVENTIVE_TEMPS_MARCHE_ONLY_TYPES } = require('../utils/motorSensorRoutineSeuil');

async function findTechnicianByRequestId(rawId) {
    const id = String(rawId || '').trim();
    if (!id) return null;
    let t = await Technician.findOne({ technicianId: id });
    if (t) return t;
    const oid = toObjectIdOrNull(id);
    if (oid) {
        t = await Technician.findById(oid);
        if (t) return t;
    }
    if (id.includes('@')) {
        t = await Technician.findOne({ email: id.toLowerCase().trim() });
        if (t) return t;
    }
    return null;
}

async function resolveMachineByRequestId(raw) {
    const id = String(raw || '').trim();
    if (!id) return null;
    if (mongoose.Types.ObjectId.isValid(id)) {
        const byOid = await Machine.findById(id);
        if (byOid) return byOid;
    }
    return Machine.findOne({ machineId: id });
}

async function enrichControlesWithMachines(controles) {
    const list = controles.map((c) => (c.toObject ? c.toObject() : { ...c }));
    const ids = [...new Set(list.map((c) => String(c.machineId || '').trim()).filter(Boolean))];
    if (!ids.length) return list;
    const machines = await Machine.find({ _id: { $in: ids } })
        .select('tempsMarche status name location')
        .lean();
    const map = new Map(machines.map((m) => [String(m._id), m]));
    for (const o of list) {
        const m = map.get(String(o.machineId || '').trim());
        if (!m) continue;
        const tm = m.tempsMarche || {};
        o.machineTempsMarcheLive = typeof tm.totalHeures === 'number' ? tm.totalHeures : 0;
        o.machineDebutSessionMarche = tm.debutSessionMarche ?? null;
        o.machineEnMarche = m.status === 'RUNNING';
        o.machineStatus = m.status;
        o.machineLocation = m.location != null && String(m.location).trim() !== '' ? String(m.location).trim() : '';
    }
    return list;
}

function toObjectIdOrNull(value) {
    if (!value) return null;
    const raw = String(value).trim();
    if (!mongoose.Types.ObjectId.isValid(raw)) return null;
    return new mongoose.Types.ObjectId(raw);
}

function isDoneStatus(raw) {
    const s = String(raw || '').toLowerCase();
    return s === 'terminé' || s === 'termine';
}

async function planNextPreventiveControlFromCompleted(controle) {
    if (!controle || controle.typeMaintenance !== 'preventive') return;
    const intervalle = Number(controle.intervalleHeures || 0);
    if (intervalle <= 0 || !controle.machineId || !controle.typeControle) return;

    const machine = await Machine.findById(String(controle.machineId));
    if (!machine) return;

    const totalHeures = Number(machine?.tempsMarche?.totalHeures || 0);
    const seuils = Array.isArray(machine.seuilsControle) ? machine.seuilsControle : [];
    const seuil = seuils.find((s) => String(s.typeControle || '').trim() === String(controle.typeControle || '').trim());
    if (!seuil) return;

    const nextThreshold = totalHeures + intervalle;
    seuil.derniereVerificationHeure = totalHeures;
    seuil.prochainControleHeure = nextThreshold;
    machine.markModified('seuilsControle');
    await machine.save();

    const alreadyOpen = await Controle.findOne({
        machineId: String(controle.machineId),
        typeControle: controle.typeControle,
        typeMaintenance: 'preventive',
        statut: { $in: ['en_attente', 'assignée', 'planifié', 'en_cours'] },
    });
    if (alreadyOpen) return;

    // Contrôles pilotés uniquement par le temps de marche : la prochaine fiche est créée par controleService.
    const typeTrim = String(controle.typeControle || '').trim();
    if (PREVENTIVE_TEMPS_MARCHE_ONLY_TYPES.includes(typeTrim)) return;

    const estimatedDueDate = new Date(Date.now() + intervalle * 60 * 60 * 1000);
    await Controle.create({
        machineId: String(controle.machineId),
        machineName: machine.name,
        typeControle: controle.typeControle,
        elementControle: controle.elementControle || controle.typeControle,
        motorType: machine.motorType || controle.motorType,
        typeMaintenance: 'preventive',
        intervalleHeures: intervalle,
        prochainControleHeure: nextThreshold,
        heuresDeClenchement: nextThreshold,
        tempsMarcheTotalHeures: totalHeures,
        dateControle: estimatedDueDate,
        datePrevue: estimatedDueDate,
        priorite: seuil.priorite || 'normale',
        statut: 'en_attente',
        notes: '',
    });
}

exports.getAllControles = async (req, res) => {
    try {
        const days = Number(req.query.days || 60);
        const fromDate = new Date(Date.now() - Math.max(days, 1) * 24 * 60 * 60 * 1000);
        const controles = await Controle.find({
            $or: [{ datePrevue: { $gte: fromDate } }, { createdAt: { $gte: fromDate } }, { statut: { $in: ['en_attente', 'assignée', 'planifié', 'en_cours'] } }],
        }).sort({ datePrevue: 1, createdAt: -1 });
        const enriched = await enrichControlesWithMachines(controles);
        res.json(enriched);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.getControlesByTechnician = async (req, res) => {
    try {
        const raw = req.params.id;
        const technician = await findTechnicianByRequestId(raw);
        const techOid = technician ? technician._id : toObjectIdOrNull(raw);

        let machineIds =
            technician && Array.isArray(technician.machineIds)
                ? technician.machineIds.map(String).filter(Boolean)
                : [];

        // Même logique que le profil Flutter : union des machines assignées + tout le parc `companyId`
        // (sinon des contrôles sur une machine « Alfa » visible pour le tech peuvent être absents de l’API).
        if (technician && technician.companyId) {
            const fleet = await Machine.find({ companyId: String(technician.companyId) })
                .select('_id')
                .lean();
            const fleetIds = fleet.map((m) => String(m._id));
            machineIds = [...new Set([...machineIds, ...fleetIds])];
        }

        const clauses = [];
        if (techOid) clauses.push({ technicienId: techOid });
        // Tous les contrôles rattachés aux machines du périmètre (assignés ou non).
        if (machineIds.length > 0) {
            clauses.push({ machineId: { $in: machineIds } });
        }

        let filter;
        if (clauses.length >= 2) {
            filter = { $or: clauses };
        } else if (clauses.length === 1) {
            filter = clauses[0];
        } else {
            const fallbackOid = toObjectIdOrNull(raw);
            if (fallbackOid) {
                filter = { technicienId: fallbackOid };
            } else {
                filter = { technicienNom: raw };
            }
        }

        const controles = await Controle.find(filter).sort({
            datePrevue: 1,
            dateControle: 1,
            createdAt: -1,
        });
        const enriched = await enrichControlesWithMachines(controles);
        res.json(enriched);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.getControlesByMachine = async (req, res) => {
    try {
        const controles = await Controle.find({ machineId: req.params.id }).sort({ dateControle: -1 });
        res.json(controles);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.updateControleStatus = async (req, res) => {
    try {
        const { statut, notes, technicienId, rapportControle } = req.body;
        const normalizedStatus = String(statut || '').trim().toLowerCase();
        if (!normalizedStatus) {
            return res.status(400).json({ message: 'Statut obligatoire' });
        }
        const statusMap = {
            'en attente': 'en_attente',
            'en_attente': 'en_attente',
            'assignée': 'assignée',
            'assignee': 'assignée',
            'planifié': 'planifié',
            'planifie': 'planifié',
            'en cours': 'en_cours',
            'en_cours': 'en_cours',
            'terminé': 'terminé',
            'termine': 'terminé',
            'annulé': 'annulé',
            'annule': 'annulé',
        };
        const finalStatus = statusMap[normalizedStatus] || statut;
        const updateData = { statut: finalStatus };
        if (notes !== undefined) updateData.notes = notes;
        if (rapportControle !== undefined) updateData.rapportControle = rapportControle;
        if (technicienId) {
            const tid = toObjectIdOrNull(technicienId);
            if (tid) {
                updateData.technicienId = tid;
                const tech = await Technician.findById(tid);
                if (tech) {
                    updateData.technicienNom = tech.name || tech.technicianId || '';
                }
            }
        }
        if (finalStatus === 'assignée') updateData.assignedAt = new Date();
        if (finalStatus === 'en_cours') updateData.startedAt = new Date();
        if (finalStatus === 'terminé') {
            updateData.completedAt = new Date();
            updateData.dateRealisation = new Date();
        }

        const controle = await Controle.findByIdAndUpdate(
            req.params.id,
            { $set: updateData },
            { new: true }
        );

        if (!controle) return res.status(404).json({ message: 'Contrôle non trouvé' });
        if (isDoneStatus(finalStatus)) {
            await planNextPreventiveControlFromCompleted(controle);
        }
        res.json(controle);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.getControlesByMonth = async (req, res) => {
    try {
        const { month } = req.params; // Format YYYY-MM
        const start = new Date(`${month}-01T00:00:00.000Z`);
        const end = new Date(start);
        end.setMonth(start.getMonth() + 1);

        const controles = await Controle.find({
            datePrevue: {
                $gte: start,
                $lt: end
            }
        }).sort({ datePrevue: 1, dateControle: 1 });

        res.json(controles);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.assignControleToTechnician = async (req, res) => {
    try {
        const { technicienId } = req.body;
        const tid = toObjectIdOrNull(technicienId);
        if (!tid) {
            return res.status(400).json({ message: 'technicienId invalide' });
        }
        const tech = await Technician.findById(tid);
        if (!tech) return res.status(404).json({ message: 'Technicien introuvable' });

        const controle = await Controle.findByIdAndUpdate(
            req.params.id,
            {
                $set: {
                    technicienId: tid,
                    technicienNom: tech.name || tech.technicianId || '',
                    statut: 'assignée',
                    assignedAt: new Date(),
                },
            },
            { new: true }
        );
        if (!controle) return res.status(404).json({ message: 'Contrôle non trouvé' });
        res.json(controle);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};

exports.getPreventiveHistory = async (req, res) => {
    try {
        const machineId = String(req.query.machineId || '').trim();
        const technicienId = String(req.query.technicienId || '').trim();
        const filter = {
            typeMaintenance: 'preventive',
            statut: 'terminé',
        };
        if (machineId) filter.machineId = machineId;
        if (technicienId) {
            const tid = toObjectIdOrNull(technicienId);
            if (tid) filter.technicienId = tid;
        }
        const items = await Controle.find(filter).sort({ dateRealisation: -1, updatedAt: -1 });
        res.json(items);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

/**
 * Saisie terrain depuis le calendrier : complète un contrôle ouvert ce jour-là,
 * ou crée une fiche « terminée » avec compte-rendu libre.
 */
exports.createSaisieTerrain = async (req, res) => {
    try {
        const compteRendu = String(req.body.compteRendu || req.body.notes || '').trim();
        const jour = String(req.body.jour || '').trim();
        const machineRaw = String(req.body.machineId || '').trim();
        const technicienRaw = String(req.body.technicienId || '').trim();
        const technicienNomBody = String(req.body.technicienNom || req.body.technicianName || '').trim();

        if (!compteRendu) {
            return res.status(400).json({ message: 'Compte rendu obligatoire' });
        }
        if (!jour || !/^\d{4}-\d{2}-\d{2}$/.test(jour)) {
            return res.status(400).json({ message: 'jour (YYYY-MM-DD) obligatoire' });
        }
        if (!machineRaw) {
            return res.status(400).json({ message: 'machineId obligatoire' });
        }

        const machine = await resolveMachineByRequestId(machineRaw);
        if (!machine) {
            return res.status(404).json({ message: 'Machine introuvable' });
        }

        const y = parseInt(jour.slice(0, 4), 10);
        const mo = parseInt(jour.slice(5, 7), 10);
        const da = parseInt(jour.slice(8, 10), 10);
        const start = new Date(Date.UTC(y, mo - 1, da, 0, 0, 0));
        const end = new Date(Date.UTC(y, mo - 1, da + 1, 0, 0, 0));

        const machineKey = String(machine._id);
        const openStatuts = ['en_attente', 'assignée', 'planifié', 'en_cours'];

        const existing = await Controle.findOne({
            machineId: machineKey,
            statut: { $in: openStatuts },
            $or: [
                { datePrevue: { $gte: start, $lt: end } },
                { dateControle: { $gte: start, $lt: end } },
            ],
        }).sort({ createdAt: -1 });

        let tid = null;
        let technicienNom = technicienNomBody;
        if (technicienRaw) {
            const techDoc = await findTechnicianByRequestId(technicienRaw);
            if (techDoc) {
                tid = techDoc._id;
                const fromDoc = String(techDoc.name || techDoc.technicianId || '').trim();
                if (fromDoc) technicienNom = fromDoc;
            } else {
                const oid = toObjectIdOrNull(technicienRaw);
                if (oid) {
                    tid = oid;
                    const tech = await Technician.findById(oid);
                    if (tech) {
                        const fromT = String(tech.name || tech.technicianId || '').trim();
                        if (fromT) technicienNom = fromT;
                    }
                }
            }
        }
        if (!technicienNom && technicienNomBody) technicienNom = technicienNomBody;

        const now = new Date();
        const rapportPayload = {
            compteRendu,
            source: 'calendrier_technicien',
            savedAt: now.toISOString(),
            termineLe: now.toISOString(),
            jour,
            ...(technicienNom ? { technicienNom } : {}),
        };

        if (existing) {
            const updated = await Controle.findByIdAndUpdate(
                existing._id,
                {
                    $set: {
                        statut: 'terminé',
                        notes: compteRendu,
                        rapportControle: rapportPayload,
                        completedAt: now,
                        dateRealisation: now,
                        ...(tid ? { technicienId: tid } : {}),
                        ...(technicienNom ? { technicienNom } : {}),
                    },
                },
                { new: true }
            );
            if (!updated) return res.status(404).json({ message: 'Contrôle introuvable' });
            if (isDoneStatus(updated.statut)) {
                await planNextPreventiveControlFromCompleted(updated);
            }
            const enriched = await enrichControlesWithMachines([updated]);
            return res.json(enriched[0]);
        }

        const pointInDay = new Date(Date.UTC(y, mo - 1, da, 12, 0, 0));
        const typeLabel =
            compteRendu.length > 120 ? `${compteRendu.substring(0, 117)}…` : compteRendu;

        const doc = await Controle.create({
            machineId: machineKey,
            machineName: machine.name,
            typeControle: typeLabel,
            elementControle: 'Saisie calendrier',
            typeMaintenance: 'corrective',
            dateControle: pointInDay,
            datePrevue: pointInDay,
            dateRealisation: now,
            priorite: 'normale',
            statut: 'terminé',
            notes: compteRendu,
            rapportControle: rapportPayload,
            completedAt: now,
            technicienId: tid || undefined,
            technicienNom: technicienNom || '',
            motorType: machine.motorType || '',
        });

        const enriched = await enrichControlesWithMachines([doc]);
        return res.status(201).json(enriched[0]);
    } catch (error) {
        res.status(400).json({ message: error.message });
    }
};
