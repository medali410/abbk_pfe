const { prisma } = require('../lib/prisma');

// ─── Helper: upsert participant ──────────────────────────────────────────────
// Called whenever someone sends a message so we can track room membership.
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
// Returns messages for a room, ordered chronologically.
// Also upserts the ChatRoom record so it always exists before messages are fetched.
async function getChatMessages(req, res) {
    try {
        const { roomId } = req.params;
        const limit = parseInt(req.query.limit || '300', 10);

        // Ensure the room exists
        await prisma.chatRoom.upsert({
            where: { roomId },
            create: { roomId },
            update: {},
        });

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
// Returns a "last-message-per-room" list: used to populate the left sidebar.
// Works for any role — each room's most recent message is returned.
async function getConceptionConversations(req, res) {
    try {
        // Fetch all rooms that have at least one message
        const rooms = await prisma.chatRoom.findMany({
            include: {
                messages: {
                    orderBy: { createdAt: 'desc' },
                    take: 1,
                },
                participants: true,
            },
            orderBy: { updatedAt: 'desc' },
            take: 50,
        });

        const result = rooms.map((room) => {
            const last = room.messages[0];
            let displayName = room.name || room.roomId;

            // Build participant names for display
            const participantNames = (room.participants || [])
                .map((p) => p.userName)
                .filter(Boolean);
            if (participantNames.length > 0 && !room.name) {
                displayName = participantNames.join(', ');
            }

            return {
                roomId: room.roomId,
                name: displayName,
                lastText: last ? last.text : 'Aucun message',
                lastAt: last ? last.createdAt : room.createdAt,
                senderName: last ? last.senderName : '',
                participants: (room.participants || []).map((p) => ({
                    userId: p.userId,
                    role: p.role,
                    userName: p.userName,
                })),
            };
        });

        return res.json(result);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/conversations/user/:userId ────────────────────────────────
// Returns conversations for a specific user (filtered by ChatRoomParticipant).
async function getConversationsByUser(req, res) {
    try {
        const userId = parseInt(req.params.userId, 10);
        if (isNaN(userId)) {
            return res.status(400).json({ error: 'userId invalide' });
        }

        const participations = await prisma.chatRoomParticipant.findMany({
            where: { userId },
            include: {
                chatRoom: {
                    include: {
                        messages: {
                            orderBy: { createdAt: 'desc' },
                            take: 1,
                        },
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
            // Show the OTHER participant's name as display name
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
            };
        });

        return res.json(result);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/conversations/role/:role ──────────────────────────────────
// Returns conversations where at least one participant has the given role.
async function getConversationsByRole(req, res) {
    try {
        const { role } = req.params;

        const participations = await prisma.chatRoomParticipant.findMany({
            where: { role },
            include: {
                chatRoom: {
                    include: {
                        messages: {
                            orderBy: { createdAt: 'desc' },
                            take: 1,
                        },
                        participants: true,
                    },
                },
            },
            orderBy: { joinedAt: 'desc' },
            take: 50,
        });

        // Deduplicate rooms (multiple participants with same role in one room)
        const seen = new Set();
        const result = [];
        for (const p of participations) {
            if (seen.has(p.roomId)) continue;
            seen.add(p.roomId);

            const room = p.chatRoom;
            const last = room.messages[0];
            const displayName = room.name || room.roomId;

            result.push({
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
            });
        }

        return res.json(result);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/concepteurs/search?query= ────────────────────────────────
// Searches concepteurs by name, location, or specialite.
// Each result includes the names of their assigned machines.
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

        // Resolve machineIds → machine names
        const results = await Promise.all(
            concepteurs.map(async (c) => {
                let machines = [];
                try {
                    const ids = JSON.parse(c.machineIds || '[]');
                    if (Array.isArray(ids) && ids.length > 0) {
                        const rows = await prisma.machine.findMany({
                            where: { id: { in: ids } },
                            select: { id: true, name: true },
                        });
                        machines = rows.map((m) => m.name);
                    }
                } catch (_) {
                    // machineIds may be malformed — ignore
                }

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

        return res.json(results);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── POST /api/chat/messages ─────────────────────────────────────────────────
// REST fallback for posting a message (used in addition to Socket.io).
// Also registers the sender as a participant.
async function postChatMessage(req, res) {
    try {
        const { roomId, from, senderName, text, userId, attachmentUrl, attachmentType } = req.body;
        if (!roomId || (!text && !attachmentUrl)) {
            return res.status(400).json({ error: 'roomId and text (or attachment) are required' });
        }

        // Ensure room exists
        await prisma.chatRoom.upsert({
            where: { roomId },
            create: { roomId },
            update: { updatedAt: new Date() },
        });

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

        // Track participant
        if (userId) {
            await _ensureParticipant(roomId, {
                userId,
                role: from || 'unknown',
                userName: senderName || '',
            });
        }

        return res.status(201).json(message);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── GET /api/chat/room/:roomId/participants ─────────────────────────────────
// Returns participants for a specific room.
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
// Manually add a participant to a room.
async function addRoomParticipant(req, res) {
    try {
        const { roomId } = req.params;
        const { userId, role, userName } = req.body;

        if (!userId) {
            return res.status(400).json({ error: 'userId is required' });
        }

        // Ensure room exists
        await prisma.chatRoom.upsert({
            where: { roomId },
            create: { roomId },
            update: {},
        });

        const uid = typeof userId === 'string' ? parseInt(userId, 10) : userId;

        const participant = await prisma.chatRoomParticipant.upsert({
            where: { roomId_userId: { roomId, userId: uid } },
            create: {
                roomId,
                userId: uid,
                role: role || 'unknown',
                userName: userName || '',
            },
            update: {
                role: role || undefined,
                userName: userName || undefined,
            },
        });

        return res.status(201).json(participant);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

const fs = require('fs');
const path = require('path');

// ─── POST /api/chat/upload ───────────────────────────────────────────────────
// Receives a base64 string and filename, saves to disk, returns URL.
async function uploadAttachment(req, res) {
    try {
        const { base64Data, filename } = req.body;
        if (!base64Data || !filename) {
            return res.status(400).json({ error: 'base64Data and filename are required' });
        }

        // Remove the data URL prefix if present (e.g., "data:image/png;base64,")
        const base64Content = base64Data.replace(/^data:([A-Za-z-+/]+);base64,/, '');

        // Create uploads directory if it doesn't exist
        const dir = path.join(__dirname, '../../uploads');
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }

        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const ext = path.extname(filename);
        const name = path.basename(filename, ext);
        const finalName = `${name}-${uniqueSuffix}${ext}`;
        const filePath = path.join(dir, finalName);

        // Write file
        const buffer = Buffer.from(base64Content, 'base64');
        fs.writeFileSync(filePath, buffer);

        // Return public URL path
        return res.json({ url: `/uploads/${finalName}` });
    } catch (err) {
        console.error('Erreur upload:', err);
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
    _ensureParticipant,
};
