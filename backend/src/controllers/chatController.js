const { prisma } = require('../lib/prisma');
const fs = require('fs');
const path = require('path');

// ─── Helper: upsert participant ──────────────────────────────────────────────
async function _ensureParticipant(roomId, { userId, role, userName }) {
    if (!userId) return;
    const uid = typeof userId === 'string' ? parseInt(userId, 10) : userId;
    if (isNaN(uid)) return;
    try {
        await prisma.chatRoomParticipant.upsert({
            where: { roomId_userId: { roomId, userId: uid } },
            create: { roomId, userId: uid, role: role || 'unknown', userName: userName || '' },
            update: { userName: userName || undefined },
        });
    } catch (_) {
        // Silently ignore — participant tracking is best-effort
    }
}

// ─── GET /api/chat/messages/:roomId ─────────────────────────────────────────
async function getChatMessages(req, res) {
    try {
        const { roomId } = req.params;
        const limit = parseInt(req.query.limit || '300', 10);

        await prisma.chatRoom.upsert({
            where: { roomId },
            create: { roomId },
            update: {},
        });

        if (roomId.startsWith('chat_conception_')) {
            const designerIdStr = roomId.replace('chat_conception_', '');
            const designerId = parseInt(designerIdStr, 10);
            if (!isNaN(designerId)) {
                await _ensureParticipant(roomId, { userId: designerId, role: 'conception' });
            }
        }

        const messages = await prisma.chatMessage.findMany({
            where: { roomId },
            orderBy: { createdAt: 'asc' },
            take: limit,
        });

        return res.json(messages);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/conversations/conception ──────────────────────────────────
async function getConceptionConversations(req, res) {
    try {
        const rooms = await prisma.chatRoom.findMany({
            include: {
                messages: { orderBy: { createdAt: 'desc' }, take: 1 },
                participants: true,
            },
            orderBy: { updatedAt: 'desc' },
            take: 50,
        });

        const result = await Promise.all(rooms.map(async (room) => {
            const last = room.messages[0];
            const participantsWithNames = await Promise.all(
                (room.participants || []).map(async (p) => {
                    const user = await prisma.user.findUnique({
                        where: { id: p.userId },
                        select: { nom: true }
                    });
                    return {
                        userId: p.userId,
                        role: p.role,
                        userName: user ? user.nom : (p.userName || 'Utilisateur inconnu'),
                    };
                })
            );

            let displayName = room.name || room.roomId;
            const otherParticipants = participantsWithNames
                .filter(p => !p.userName.toLowerCase().includes('admin'))
                .map(p => p.userName);

            if (otherParticipants.length > 0) {
                displayName = otherParticipants[0];
            } else if (participantsWithNames.length > 0) {
                displayName = participantsWithNames[0].userName;
            }

            const callerId = req.auth && req.auth.userId ? parseInt(req.auth.userId, 10) : null;
            const myPart = callerId ? (room.participants || []).find(pp => pp.userId === callerId) : null;

            return {
                roomId: room.roomId,
                name: displayName,
                lastText: last ? last.text : 'Aucun message',
                lastAt: last ? last.createdAt : room.createdAt,
                senderName: last ? last.senderName : '',
                participants: participantsWithNames,
                isPinned: myPart ? myPart.isPinned : false,
                isMuted: myPart ? myPart.isMuted : false,
            };
        }));

        return res.json(result);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/conversations/user/:userId ────────────────────────────────
async function getConversationsByUser(req, res) {
    try {
        const userId = parseInt(req.params.userId, 10);
        if (isNaN(userId)) return res.status(400).json({ error: 'userId invalide' });

        const participations = await prisma.chatRoomParticipant.findMany({
            where: { userId },
            include: {
                chatRoom: {
                    include: {
                        messages: { orderBy: { createdAt: 'desc' }, take: 1 },
                        participants: true,
                    },
                },
            },
            orderBy: { joinedAt: 'desc' },
            take: 50,
        });

        const result = participations.map((p) => {
            const room = p.chatRoom;
            const last = room.messages[0];
            const otherParticipants = (room.participants || [])
                .filter((pp) => pp.userId !== userId)
                .map((pp) => pp.userName)
                .filter(Boolean);
            const displayName = room.name || otherParticipants.join(', ') || room.roomId;

            return {
                roomId: room.roomId,
                name: displayName,
                lastText: last ? last.text : 'Aucun message',
                lastAt: last ? last.createdAt : room.createdAt,
                senderName: last ? last.senderName : '',
                participants: (room.participants || []).map((pp) => ({
                    userId: pp.userId,
                    role: pp.role,
                    userName: pp.userName,
                })),
                isPinned: p.isPinned ?? false,
                isMuted: p.isMuted ?? false,
            };
        });

        return res.json(result);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/conversations/role/:role ──────────────────────────────────
async function getConversationsByRole(req, res) {
    try {
        const { role } = req.params;
        const participations = await prisma.chatRoomParticipant.findMany({
            where: { role },
            include: {
                chatRoom: {
                    include: {
                        messages: { orderBy: { createdAt: 'desc' }, take: 1 },
                        participants: true,
                    },
                },
            },
            orderBy: { joinedAt: 'desc' },
            take: 50,
        });

        const seen = new Set();
        const roomsToProcess = [];
        for (const p of participations) {
            if (seen.has(p.roomId)) continue;
            seen.add(p.roomId);
            roomsToProcess.push(p.chatRoom);
        }

        const result = await Promise.all(roomsToProcess.map(async (room) => {
            const last = room.messages[0];
            const participantsWithNames = await Promise.all(
                (room.participants || []).map(async (p) => {
                    const user = await prisma.user.findUnique({
                        where: { id: p.userId },
                        select: { nom: true }
                    });
                    return {
                        userId: p.userId,
                        role: p.role,
                        userName: user ? user.nom : (p.userName || 'Utilisateur inconnu'),
                    };
                })
            );

            let displayName = room.name || room.roomId;
            const otherParticipants = participantsWithNames
                .filter(p => !p.userName.toLowerCase().includes('admin'))
                .map(p => p.userName);

            if (otherParticipants.length > 0) displayName = otherParticipants[0];
            else if (participantsWithNames.length > 0) displayName = participantsWithNames[0].userName;

            return {
                roomId: room.roomId,
                name: displayName,
                lastText: last ? last.text : 'Aucun message',
                lastAt: last ? last.createdAt : room.createdAt,
                senderName: last ? last.senderName : '',
                participants: participantsWithNames,
            };
        }));

        return res.json(result);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/concepteurs/search?query= ────────────────────────────────
async function searchConcepteurs(req, res) {
    try {
        const query = (req.query.query || '').trim();
        const where = query
            ? {
                OR: [
                    { user: { nom: { contains: query, mode: 'insensitive' } } },
                    { location: { contains: query, mode: 'insensitive' } },
                    { specialite: { contains: query, mode: 'insensitive' } },
                ],
            }
            : {};

        const concepteurs = await prisma.concepteur.findMany({
            where,
            include: { user: true },
            orderBy: { id: 'desc' },
            take: 30,
        });

        const results = await Promise.all(
            concepteurs.map(async (c) => {
                let machines = [];
                try {
                    const rows = await prisma.machine.findMany({
                        where: { concepteurId: String(c.id) },
                        select: { id: true, name: true },
                    });
                    machines = rows.map((m) => m.name || m.id);
                    if (machines.length === 0) {
                        const ids = JSON.parse(c.machineIds || '[]');
                        if (Array.isArray(ids) && ids.length > 0) {
                            const fallbackRows = await prisma.machine.findMany({
                                where: { id: { in: ids } },
                                select: { id: true, name: true },
                            });
                            machines = fallbackRows.map((m) => m.name || m.id);
                        }
                    }
                } catch (_) { }

                return {
                    id: c.userId,
                    concepteurId: c.id,
                    name: c.user.nom,
                    email: c.user.email,
                    location: c.location,
                    specialite: c.specialite,
                    machines,
                };
            }),
        );

        let blockedIds = [];
        const callerId = req.auth ? parseInt(req.auth.userId, 10) : null;
        if (callerId) {
            const blocks = await prisma.userBlock.findMany({ where: { blockerId: callerId } });
            blockedIds = blocks.map(b => b.blockedId);
        }

        const filteredResults = results.filter(r => !blockedIds.includes(r.id));
        return res.json(filteredResults);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── POST /api/chat/messages ─────────────────────────────────────────────────
async function postChatMessage(req, res) {
    try {
        const { roomId, from, senderName, text, userId, attachmentUrl, attachmentType } = req.body;
        if (!roomId || (!text && !attachmentUrl)) {
            return res.status(400).json({ error: 'roomId and text (or attachment) are required' });
        }

        await prisma.chatRoom.upsert({
            where: { roomId },
            create: { roomId },
            update: { updatedAt: new Date() },
        });

        if (roomId.startsWith('chat_conception_')) {
            const designerIdStr = roomId.replace('chat_conception_', '');
            const designerId = parseInt(designerIdStr, 10);
            if (!isNaN(designerId)) {
                await _ensureParticipant(roomId, { userId: designerId, role: 'conception' });
            }
        }

        const message = await prisma.chatMessage.create({
            data: {
                roomId,
                from: from || 'unknown',
                senderName: senderName || 'Inconnu',
                text: text || '',
                attachmentUrl,
                attachmentType,
            },
        });

        if (userId) {
            await _ensureParticipant(roomId, {
                userId,
                role: from || 'unknown',
                userName: senderName || '',
            });
        }

        // Notify admins if sent by a concepteur
        if (from === 'conception') {
            const admins = await prisma.admin.findMany({ select: { userId: true } });
            const ops = admins.map(admin => prisma.notification.create({
                data: {
                    userId: admin.userId,
                    role: 'admin',
                    type: 'NEW_MESSAGE',
                    title: 'Nouveau message',
                    body: `Message de ${senderName || 'un concepteur'}`,
                    isRead: false
                }
            }));
            await Promise.all(ops);
        }

        return res.status(201).json(message);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/room/:roomId/participants ─────────────────────────────────
async function getRoomParticipants(req, res) {
    try {
        const { roomId } = req.params;
        const participants = await prisma.chatRoomParticipant.findMany({
            where: { roomId },
            orderBy: { joinedAt: 'asc' },
        });
        return res.json(participants);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── POST /api/chat/room/:roomId/participants ────────────────────────────────
async function addRoomParticipant(req, res) {
    try {
        const { roomId } = req.params;
        const { userId, role, userName } = req.body;
        if (!userId) return res.status(400).json({ error: 'userId is required' });

        await prisma.chatRoom.upsert({
            where: { roomId },
            create: { roomId },
            update: {},
        });

        const uid = typeof userId === 'string' ? parseInt(userId, 10) : userId;
        const participant = await prisma.chatRoomParticipant.upsert({
            where: { roomId_userId: { roomId, userId: uid } },
            create: { roomId, userId: uid, role: role || 'unknown', userName: userName || '' },
            update: { role: role || undefined, userName: userName || undefined },
        });

        return res.status(201).json(participant);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── POST /api/chat/upload ───────────────────────────────────────────────────
async function uploadAttachment(req, res) {
    try {
        const { base64Data, filename } = req.body;
        if (!base64Data || !filename) {
            return res.status(400).json({ error: 'base64Data and filename are required' });
        }

        const base64Content = base64Data.replace(/^data:([A-Za-z-+/]+);base64,/, '');
        const dir = path.join(__dirname, '../../uploads');
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const ext = path.extname(filename);
        const name = path.basename(filename, ext);
        const finalName = `${name}-${uniqueSuffix}${ext}`;
        const filePath = path.join(dir, finalName);

        const buffer = Buffer.from(base64Content, 'base64');
        fs.writeFileSync(filePath, buffer);

        return res.json({ url: `/uploads/${finalName}` });
    } catch (err) {
        console.error('Erreur upload:', err);
        return res.status(500).json({ error: err.message });
    }
}

// ─── DELETE /api/chat/messages/:messageId ────────────────────────────────────
async function deleteChatMessage(req, res) {
    try {
        const { messageId } = req.params;
        await prisma.chatMessage.delete({ where: { id: parseInt(messageId) } });
        return res.json({ success: true, message: 'Message supprimé' });
    } catch (err) {
        console.error('Erreur suppression message:', err);
        return res.status(500).json({ error: err.message });
    }
}

// ─── DELETE /api/chat/rooms/:roomId ──────────────────────────────────────────
async function deleteChatRoom(req, res) {
    try {
        const { roomId } = req.params;
        await prisma.chatRoom.delete({ where: { roomId } });
        return res.json({ message: 'Discussion supprimée avec succès' });
    } catch (err) {
        if (err.code === 'P2025') return res.status(404).json({ error: 'Discussion introuvable' });
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/contacts/technician ─────────────────────────────────────
async function getTechnicianContacts(req, res) {
    try {
        const userId = parseInt(req.auth.userId, 10);
        if (isNaN(userId)) return res.status(400).json({ error: 'userId invalide' });

        const tech = await prisma.technician.findUnique({ where: { userId } });
        if (!tech) return res.status(404).json({ error: 'Profil technicien introuvable' });

        let machineIds = [];
        try { machineIds = JSON.parse(tech.machineIds || '[]'); } catch (e) { machineIds = []; }

        if (!Array.isArray(machineIds) || machineIds.length === 0) return res.json([]);

        const contacts = [];

        for (const mId of machineIds) {
            const machine = await prisma.machine.findUnique({ where: { id: mId } });
            if (!machine) continue;

            if (machine.concepteurId) {
                const concepteur = await prisma.concepteur.findUnique({
                    where: { id: parseInt(machine.concepteurId, 10) },
                    include: { user: true }
                });
                if (concepteur && !contacts.find(c => c.id === concepteur.userId && c.role === 'conception')) {
                    contacts.push({
                        id: concepteur.userId,
                        name: concepteur.user?.nom || `Concepteur ${concepteur.id}`,
                        role: 'conception',
                        roleLabel: `Concepteur de la machine ${machine.name || machine.id}`,
                        machineId: machine.id
                    });
                }
            }

            const agents = await prisma.maintenanceAgent.findMany({
                where: { machineIds: { contains: `"${machine.id}"` } },
                include: { user: true }
            });
            for (const a of agents) {
                if (a.userId === userId) continue;
                if (!contacts.find(c => c.id === a.userId && c.role === 'maintenance')) {
                    contacts.push({
                        id: a.userId,
                        name: a.user?.nom || `${a.firstName} ${a.lastName}`,
                        role: 'maintenance',
                        roleLabel: `Agent de maintenance de la machine ${machine.name || machine.id}`,
                        machineId: machine.id
                    });
                }
            }

            if (machine.companyId) {
                const clients = await prisma.client.findMany({
                    where: { clientId: machine.companyId },
                    include: { user: true }
                });
                for (const c of clients) {
                    if (!contacts.find(ct => ct.id === c.userId && ct.role === 'client')) {
                        contacts.push({
                            id: c.userId,
                            name: c.user?.nom || `Client ${c.clientId}`,
                            role: 'client',
                            roleLabel: `Client de la machine ${machine.name || machine.id}`,
                            machineId: machine.id
                        });
                    }
                }
            }
        }

        return res.json(contacts);
    } catch (err) {
        console.error('Erreur getTechnicianContacts:', err);
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/contacts/concepteur ─────────────────────────────────────
async function getConcepteurContacts(req, res) {
    try {
        const userId = parseInt(req.auth.userId, 10);
        if (isNaN(userId)) return res.status(400).json({ error: 'userId invalide' });

        const role = String(req.auth.role || '').toLowerCase();
        const isAdmin = role === 'admin' || role === 'superadmin';

        if (isAdmin) {
            const contacts = [];
            const concepteurs = await prisma.concepteur.findMany({ include: { user: true } });
            for (const c of concepteurs) {
                let machines = [];
                try {
                    const rows = await prisma.machine.findMany({
                        where: { concepteurId: String(c.id) },
                        select: { id: true, name: true }
                    });
                    machines = rows.map(m => m.name || m.id);
                    if (machines.length === 0) {
                        const ids = JSON.parse(c.machineIds || '[]');
                        if (Array.isArray(ids) && ids.length > 0) {
                            const fallbackRows = await prisma.machine.findMany({
                                where: { id: { in: ids } },
                                select: { id: true, name: true }
                            });
                            machines = fallbackRows.map(m => m.name || m.id);
                        }
                    }
                } catch (_) { }

                contacts.push({
                    id: c.userId,
                    concepteurId: c.id,
                    name: c.user?.nom || `Concepteur ${c.id}`,
                    role: 'conception',
                    roleLabel: `Concepteur`,
                    machines: machines
                });
            }
            return res.json(contacts);
        }

        const concepteur = await prisma.concepteur.findUnique({ where: { userId } });
        if (!concepteur) return res.status(404).json({ error: 'Profil concepteur introuvable' });

        const machines = await prisma.machine.findMany({
            where: { concepteurId: String(concepteur.id) }
        });

        if (machines.length === 0) return res.json([]);

        const contacts = [];

        for (const machine of machines) {
            const techs = await prisma.technician.findMany({
                where: { machineIds: { contains: `"${machine.id}"` } },
                include: { user: true }
            });
            for (const t of techs) {
                if (!contacts.find(c => c.id === t.userId && c.role === 'technician')) {
                    contacts.push({
                        id: t.userId,
                        name: t.user?.nom || `${t.firstName} ${t.lastName}`,
                        role: 'technician',
                        roleLabel: `Technicien de la machine ${machine.name || machine.id}`,
                        machineId: machine.id
                    });
                }
            }

            const agents = await prisma.maintenanceAgent.findMany({
                where: { machineIds: { contains: `"${machine.id}"` } },
                include: { user: true }
            });
            for (const a of agents) {
                if (!contacts.find(c => c.id === a.userId && c.role === 'maintenance')) {
                    contacts.push({
                        id: a.userId,
                        name: a.user?.nom || `${a.firstName} ${a.lastName}`,
                        role: 'maintenance',
                        roleLabel: `Agent de maintenance de la machine ${machine.name || machine.id}`,
                        machineId: machine.id
                    });
                }
            }

            if (machine.companyId) {
                const clients = await prisma.client.findMany({
                    where: { clientId: machine.companyId },
                    include: { user: true }
                });
                for (const c of clients) {
                    if (!contacts.find(ct => ct.id === c.userId && ct.role === 'client')) {
                        contacts.push({
                            id: c.userId,
                            name: c.user?.nom || `Client ${c.clientId}`,
                            role: 'client',
                            roleLabel: `Client de la machine ${machine.name || machine.id}`,
                            machineId: machine.id
                        });
                    }
                }
            }
        }

        return res.json(contacts);
    } catch (err) {
        console.error('Erreur getConcepteurContacts:', err);
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/contacts/client ─────────────────────────────────────────
async function getClientContacts(req, res) {
    try {
        const userId = parseInt(req.auth.userId, 10);
        if (isNaN(userId)) return res.status(400).json({ error: 'userId invalide' });

        const client = await prisma.client.findUnique({ where: { userId } });
        if (!client) return res.status(404).json({ error: 'Profil client introuvable' });

        const machines = await prisma.machine.findMany({
            where: { companyId: client.clientId }
        });

        if (machines.length === 0) return res.json([]);

        const contacts = [];

        for (const machine of machines) {
            if (machine.concepteurId) {
                const concepteur = await prisma.concepteur.findUnique({
                    where: { id: parseInt(machine.concepteurId, 10) },
                    include: { user: true }
                });
                if (concepteur && !contacts.find(c => c.id === concepteur.userId && c.role === 'conception')) {
                    contacts.push({
                        id: concepteur.userId,
                        subId: concepteur.id,
                        name: concepteur.user?.nom || `Concepteur ${concepteur.id}`,
                        role: 'conception',
                        roleLabel: `Concepteur de la machine ${machine.name || machine.id}`,
                        machineId: machine.id
                    });
                }
            }

            const techs = await prisma.technician.findMany({
                where: { machineIds: { contains: `"${machine.id}"` } },
                include: { user: true }
            });
            for (const t of techs) {
                if (!contacts.find(c => c.id === t.userId && c.role === 'technician')) {
                    contacts.push({
                        id: t.userId,
                        subId: t.technicianId || t.id,
                        name: t.user?.nom || `${t.firstName} ${t.lastName}`,
                        role: 'technician',
                        roleLabel: `Technicien de la machine ${machine.name || machine.id}`,
                        machineId: machine.id
                    });
                }
            }

            const agents = await prisma.maintenanceAgent.findMany({
                where: { machineIds: { contains: `"${machine.id}"` } },
                include: { user: true }
            });
            for (const a of agents) {
                if (!contacts.find(c => c.id === a.userId && c.role === 'maintenance')) {
                    contacts.push({
                        id: a.userId,
                        subId: a.maintenanceAgentId || a.id,
                        name: a.user?.nom || `${a.firstName} ${a.lastName}`,
                        role: 'maintenance',
                        roleLabel: `Agent de maintenance de la machine ${machine.name || machine.id}`,
                        machineId: machine.id
                    });
                }
            }
        }

        return res.json(contacts);
    } catch (err) {
        console.error('Erreur getClientContacts:', err);
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/contacts/maintenance ─────────────────────────────────────
async function getMaintenanceAgentContacts(req, res) {
    try {
        const userId = parseInt(req.auth.userId, 10);
        if (isNaN(userId)) return res.status(400).json({ error: 'userId invalide' });

        const agent = await prisma.maintenanceAgent.findUnique({ where: { userId } });
        if (!agent) return res.status(404).json({ error: 'Profil agent de maintenance introuvable' });

        let machineIds = [];
        try { machineIds = JSON.parse(agent.machineIds || '[]'); } catch (e) { machineIds = []; }

        if (!Array.isArray(machineIds) || machineIds.length === 0) return res.json([]);

        const contacts = [];

        for (const mId of machineIds) {
            const machine = await prisma.machine.findUnique({ where: { id: mId } });
            if (!machine) continue;

            if (machine.concepteurId) {
                const concepteur = await prisma.concepteur.findUnique({
                    where: { id: parseInt(machine.concepteurId, 10) },
                    include: { user: true }
                });
                if (concepteur && !contacts.find(c => c.id === concepteur.userId && c.role === 'conception')) {
                    contacts.push({
                        id: concepteur.userId,
                        name: concepteur.user?.nom || `Concepteur ${concepteur.id}`,
                        role: 'conception',
                        roleLabel: `Concepteur de la machine ${machine.name || machine.id}`,
                        machineId: machine.id
                    });
                }
            }

            const techs = await prisma.technician.findMany({
                where: { machineIds: { contains: `"${machine.id}"` } },
                include: { user: true }
            });
            for (const t of techs) {
                if (!contacts.find(c => c.id === t.userId && c.role === 'technician')) {
                    contacts.push({
                        id: t.userId,
                        name: t.user?.nom || `${t.firstName} ${t.lastName}`,
                        role: 'technician',
                        roleLabel: `Technicien de la machine ${machine.name || machine.id}`,
                        machineId: machine.id
                    });
                }
            }

            if (machine.companyId) {
                const clients = await prisma.client.findMany({
                    where: { clientId: machine.companyId },
                    include: { user: true }
                });
                for (const c of clients) {
                    if (!contacts.find(ct => ct.id === c.userId && ct.role === 'client')) {
                        contacts.push({
                            id: c.userId,
                            name: c.user?.nom || `Client ${c.clientId}`,
                            role: 'client',
                            roleLabel: `Client de la machine ${machine.name || machine.id}`,
                            machineId: machine.id
                        });
                    }
                }
            }
        }

        return res.json(contacts);
    } catch (err) {
        console.error('Erreur getMaintenanceAgentContacts:', err);
        return res.status(500).json({ error: err.message });
    }
}

// ─── NEW MESSAGE/ROOM ACTIONS ────────────────────────────────────────────────
async function togglePinRoom(req, res) {
    try {
        const userId = parseInt(req.auth.userId, 10);
        const { roomId } = req.params;
        const { isPinned } = req.body;
        if (isNaN(userId)) return res.status(400).json({ error: 'userId invalide' });

        await prisma.chatRoomParticipant.updateMany({
            where: { roomId, userId },
            data: { isPinned: !!isPinned }
        });
        return res.json({ success: true, isPinned: !!isPinned });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function toggleMuteRoom(req, res) {
    try {
        const userId = parseInt(req.auth.userId, 10);
        const { roomId } = req.params;
        const { isMuted } = req.body;
        if (isNaN(userId)) return res.status(400).json({ error: 'userId invalide' });

        await prisma.chatRoomParticipant.updateMany({
            where: { roomId, userId },
            data: { isMuted: !!isMuted }
        });
        return res.json({ success: true, isMuted: !!isMuted });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function clearRoomHistory(req, res) {
    try {
        const { roomId } = req.params;
        await prisma.chatMessage.deleteMany({
            where: { roomId }
        });
        return res.json({ success: true, message: 'Historique effacé' });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── USER BLOCKING ACTIONS ───────────────────────────────────────────────────
async function blockUser(req, res) {
    try {
        const blockerId = parseInt(req.auth.userId, 10);
        const blockedId = parseInt(req.body.blockedId, 10);
        if (isNaN(blockerId) || isNaN(blockedId)) return res.status(400).json({ error: 'IDs invalides' });

        await prisma.userBlock.upsert({
            where: { blockerId_blockedId: { blockerId, blockedId } },
            create: { blockerId, blockedId },
            update: {}
        });
        return res.json({ success: true, message: 'Utilisateur bloqué' });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function unblockUser(req, res) {
    try {
        const blockerId = parseInt(req.auth.userId, 10);
        const blockedId = parseInt(req.params.blockedId, 10);
        if (isNaN(blockerId) || isNaN(blockedId)) return res.status(400).json({ error: 'IDs invalides' });

        await prisma.userBlock.deleteMany({
            where: { blockerId, blockedId }
        });
        return res.json({ success: true, message: 'Utilisateur débloqué' });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getBlockedUsers(req, res) {
    try {
        const blockerId = parseInt(req.auth.userId, 10);
        if (isNaN(blockerId)) return res.status(400).json({ error: 'userId invalide' });

        const blocks = await prisma.userBlock.findMany({
            where: { blockerId }
        });
        return res.json(blocks.map(b => b.blockedId));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = {
    getChatMessages,
    getConceptionConversations,
    getConversationsByUser,
    getConversationsByRole,
    searchConcepteurs,
    postChatMessage,
    getRoomParticipants,
    addRoomParticipant,
    uploadAttachment,
    deleteChatRoom,
    deleteChatMessage,
    getConcepteurContacts,
    getTechnicianContacts,
    getClientContacts,
    getMaintenanceAgentContacts,
    _ensureParticipant,
    togglePinRoom,
    toggleMuteRoom,
    clearRoomHistory,
    blockUser,
    unblockUser,
    getBlockedUsers,
};
