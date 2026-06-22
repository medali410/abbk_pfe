// src/controllers/diagnosticInterventionsController.js
const fs = require('fs');
const path = require('path');
const { prisma } = require('../lib/prisma');

const dataPath = path.join(__dirname, '../../../diagnostic-interventions.json');

function loadData() {
    try {
        if (fs.existsSync(dataPath)) {
            return JSON.parse(fs.readFileSync(dataPath, 'utf8'));
        }
    } catch (e) {
        console.error('Error loading diagnostic-interventions.json', e);
    }
    return [];
}

function saveData(data) {
    try {
        fs.writeFileSync(dataPath, JSON.stringify(data, null, 2));
    } catch (e) {
        console.error('Error saving diagnostic-interventions.json', e);
    }
}

let interventions = loadData();

async function getDiagnosticInterventions(req, res) {
    res.json(interventions);
}

async function getOneDiagnosticIntervention(req, res) {
    const intervention = interventions.find(i => i.id === req.params.id);
    if (!intervention) return res.status(404).json({ error: 'Intervention not found' });
    res.json(intervention);
}

async function createDiagnosticIntervention(req, res) {
    const { machineId, technicianId, scenarioType, summary } = req.body;
    const newInt = {
        id: Date.now().toString(),
        machineId,
        technicianId: technicianId || '',
        scenarioType: scenarioType || 'DEFAULT',
        summary: summary || '',
        status: 'PENDING',
        messages: [],
        coordinationNotes: [],
        createdAt: new Date().toISOString()
    };
    interventions.push(newInt);
    saveData(interventions);
    res.status(201).json(newInt);
}

async function addMessage(req, res) {
    const id = req.params.id;
    const { content, authorName } = req.body;
    const intervention = interventions.find(i => i.id === id);
    if (!intervention) return res.status(404).json({ error: 'Intervention not found' });
    
    const msg = {
        id: Date.now().toString(),
        content,
        authorName: authorName || 'Unknown',
        createdAt: new Date().toISOString()
    };
    intervention.messages.push(msg);
    saveData(interventions);

    const io = req.app.get('io');
    if (io) {
        io.emit('diagnostic_message', {
            interventionId: id,
            message: msg
        });
    }

    res.json(msg);
}

async function addCoordination(req, res) {
    const id = req.params.id;
    const { content, authorName, isMission } = req.body;
    const intervention = interventions.find(i => i.id === id);
    if (!intervention) return res.status(404).json({ error: 'Intervention not found' });

    const isM = isMission === true || isMission === 'true';
    const note = {
        id: Date.now().toString(),
        content,
        authorName: authorName || 'Unknown',
        isMission: isM,
        missionStatus: isM ? 'SENT' : null,
        createdAt: new Date().toISOString()
    };
    intervention.coordinationNotes.push(note);
    saveData(interventions);

    const io = req.app.get('io');
    if (io) {
        io.emit('diagnostic_coordination', {
            interventionId: id,
            note: note
        });

        // 🚀 Si c'est une mission, on émet également l'événement de Toast
        if (isM) {
            try {
                const missionPayload = {
                    title: 'Mission d\'inspection',
                    description: content,
                    senderName: authorName || 'Maintenance',
                    machineName: intervention.machineName,
                    machineId: intervention.machineId,
                    techName: 'Technicien' // Simplifié si on n'a pas son nom exact
                };
                
                io.to(`global_user_${intervention.technicianId}`).emit('new_mission', {
                    mission: missionPayload,
                    type: 'MISSION_ASSIGNED'
                });
            } catch (err) {
                console.error("Erreur lors de l'émission new_mission:", err);
            }
        }
    }

    res.json({ note });
}

async function updateCoordinationStatus(req, res) {
    const { id, noteId } = req.params;
    const { status } = req.body;

    const intervention = interventions.find(i => i.id === id);
    if (!intervention) return res.status(404).json({ error: 'Intervention not found' });

    const note = intervention.coordinationNotes.find(n => n.id === noteId);
    if (!note) return res.status(404).json({ error: 'Note not found' });

    note.missionStatus = status;
    if (status === 'CONFIRMED' || status === 'STARTED') {
        note.missionConfirmedAt = new Date().toISOString();
    } else if (status === 'COMPLETED' || status === 'DONE') {
        note.missionCompletedAt = new Date().toISOString();
    }
    saveData(interventions);

    const io = req.app.get('io');
    if (io) {
        io.emit('diagnostic_coordination_update', {
            interventionId: id,
            noteId: noteId,
            status: status
        });

        if (note.isMission) {
            (async () => {
                try {
                    // Enrichissement pour le toast
                    let concepteurId = null;
                    if (intervention.machineId) {
                        const machine = await prisma.machine.findUnique({ where: { id: intervention.machineId } });
                        if (machine) concepteurId = machine.concepteurId;
                    }

                    // On essaie de retrouver l'ID de l'agent de maintenance qui a créé la mission (par son nom)
                    let authorUserId = null;
                    if (note.authorName) {
                        const user = await prisma.user.findFirst({
                            where: { nom: note.authorName }
                        });
                        if (!user) {
                            // On tente avec le prénom ou nom de MaintenanceAgent
                            const agents = await prisma.maintenanceAgent.findMany({ include: { user: true } });
                            const agent = agents.find(a => `${a.firstName} ${a.lastName}`.trim() === note.authorName);
                            if (agent) authorUserId = agent.userId;
                        } else {
                            authorUserId = user.id;
                        }
                    }

                    const missionPayload = {
                        title: 'Mission d\'inspection',
                        description: note.content,
                        senderName: note.authorName || 'Maintenance',
                        machineName: intervention.machineName,
                        machineId: intervention.machineId,
                        techName: 'Technicien'
                    };

                    if ((status === 'COMPLETED' || status === 'DONE') && concepteurId) {
                        io.to(`global_user_${concepteurId}`).emit('mission_completed', { mission: missionPayload });
                    }

                    if ((status === 'CONFIRMED' || status === 'STARTED' || status === 'COMPLETED' || status === 'DONE') && authorUserId) {
                        io.to(`global_user_${authorUserId}`).emit('mission_status_updated', {
                            mission: missionPayload,
                            status: status === 'CONFIRMED' || status === 'STARTED' ? 'IN_PROGRESS' : 'DONE'
                        });
                    }
                } catch (err) {
                    console.error("Erreur émission toast mission_completed/mission_status_updated:", err);
                }
            })();
        }
    }

    res.json({ note });
}

async function updateMessageStatus(req, res) {
    const { id, messageId } = req.params;
    const { status } = req.body;

    const intervention = interventions.find(i => i.id === id);
    if (!intervention) return res.status(404).json({ error: 'Intervention not found' });

    const msg = intervention.messages.find(m => m.id === messageId || m._id === messageId);
    if (!msg) return res.status(404).json({ error: 'Message not found' });

    msg.missionStatus = status;
    saveData(interventions);

    const io = req.app.get('io');
    if (io) {
        io.emit('diagnostic_message_status_update', {
            interventionId: id,
            messageId: messageId,
            status: status
        });
    }

    res.json({ message: msg });
}

module.exports = {
    getDiagnosticInterventions,
    getOneDiagnosticIntervention,
    createDiagnosticIntervention,
    addMessage,
    addCoordination,
    updateCoordinationStatus,
    updateMessageStatus
};
