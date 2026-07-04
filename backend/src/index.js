// src/index.js  (version mise à jour — intègre les nouvelles routes)
// ─── Seules les lignes modifiées/ajoutées sont marquées [AJOUT] ──────────────

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');

const authRoutes = require('./routes/auth');
const clientsRoutes = require('./routes/clients');
const machinesRoutes = require('./routes/machines');
const dashboardRoutes = require('./routes/dashboard');
const actorsRoutes = require('./routes/actors');
const documentsRoutes = require('./routes/documents');
const telemetryRoutes = require('./routes/telemetry');
const chatRoutes = require('./routes/chat');
const purchaseRequestsRoutes = require('./routes/purchaseRequests');

// [AJOUT] Nouvelles routes dédiées Technicien et Agent de Maintenance
const techniciansRoutes = require('./routes/technicians');        // [AJOUT]
const maintenanceAgentsRoutes = require('./routes/maintenanceAgents'); // [AJOUT]
const controlesRoutes = require('./routes/controles');          // [AJOUT]
const maintenanceOrdersRoutes = require('./routes/maintenanceOrders'); // [AJOUT]
const consultationRoutes = require('./routes/consultations');
const notificationRoutes = require('./routes/notifications');
const missionRoutes = require('./routes/missions');
const predictionRoutes = require('./routes/predictions');
const diagnosticInterventionRoutes = require('./routes/diagnosticInterventions');

const healthController = require('./controllers/healthController');
const telemetryController = require('./controllers/telemetryController');
const { prisma } = require('./lib/prisma');

const PORT = parseInt(String(process.env.PORT || '3001'), 10);
const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: true, credentials: true }, allowEIO3: true });

app.set('io', io); // Save IO to be used in controllers

// Initialiser la connexion MQTT
const { initMqtt } = require('./lib/mqtt');
initMqtt(io);

app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '50mb' }));

const path = require('path');
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

// Health check
app.get('/api/health', healthController.check);

app.post('/api/temp-create-concepteur', async (req, res) => {
    try {
        const { createUserWithProfile } = require('./lib/auth');
        const { user, profile } = await createUserWithProfile(
            'conception',
            { email: 'sloma4694@gmail.com', nom: 'lemjid', password: 'password123', adresse: 'Tunis' },
            { location: 'Tunis', specialite: 'Conception', status: 'Actif' }
        );
        res.json({ user, profile });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ─── Routes ───────────────────────────────────────────────────────────────────
app.use('/api', authRoutes);
app.use('/api/clients', clientsRoutes);
app.use('/api/machines', machinesRoutes);
app.use('/api/machine-instances', require('./routes/machineInstances')); // [AJOUT]
app.use('/api/predictions', predictionRoutes);
app.use('/api', predictionRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api', actorsRoutes);            // garde la compatibilité avec /api/concepteurs
app.use('/api/conceptions', documentsRoutes);
app.use('/api/documents', documentsRoutes);
app.use('/api', telemetryRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/purchase-requests', purchaseRequestsRoutes);

// [AJOUT] Routes dédiées Technicien et Agent de Maintenance
app.use('/api/technicians', techniciansRoutes);        // [AJOUT]
app.use('/api/maintenance-agents', maintenanceAgentsRoutes);  // [AJOUT]
app.use('/api/controles', controlesRoutes);          // [AJOUT]
app.use('/api/maintenance-orders', maintenanceOrdersRoutes);  // [AJOUT]
app.use('/api/consultations', consultationRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/missions', missionRoutes);
app.use('/api/diagnostic-interventions', diagnosticInterventionRoutes);

// ─── Socket.io ────────────────────────────────────────────────────────────────
const chatController = require('./controllers/chatController');

io.on('connection', (socket) => {
    console.log('🔌 Client connecté via Socket.io:', socket.id);

    socket.on('join_global_notifications', (data) => {
        if (data && data.token) {
            try {
                const decoded = jwt.verify(data.token, process.env.JWT_SECRET || 'abbk_secret_key_2024');
                const globalRoom = `global_user_${decoded.id}`;
                socket.join(globalRoom);
                console.log(`🔔 Socket ${socket.id} (User ${decoded.id}) a rejoint la salle globale : ${globalRoom}`);
            } catch (err) {
                console.error(`❌ Token JWT invalide pour join_global_notifications:`, err.message);
            }
        }
    });

    socket.on('join_chat_room', (data) => {
        if (data.roomId) {
            socket.join(data.roomId);
            console.log(`💬 Socket ${socket.id} a rejoint la salle : ${data.roomId}`);
        }
    });

    socket.on('disconnect', () => {
        console.log(`🔴 Socket déconnecté: ${socket.id}`);
    });

    socket.on('chat_message', async (data) => {
        try {
            const { roomId, from, senderName, text, userId, attachmentUrl, attachmentType } = data;
            if (!roomId || (!text && !attachmentUrl)) return;

            await prisma.chatRoom.upsert({
                where: { roomId },
                create: { roomId },
                update: { updatedAt: new Date() },
            });

            const msg = await prisma.chatMessage.create({
                data: { roomId, from, senderName, text: text || '', attachmentUrl, attachmentType },
            });

            if (userId) {
                await chatController._ensureParticipant(roomId, {
                    userId,
                    role: from || 'unknown',
                    userName: senderName || '',
                });
            }

            if (roomId.startsWith('chat_conception_')) {
                const designerId = parseInt(roomId.replace('chat_conception_', ''), 10);
                if (!isNaN(designerId)) {
                    await chatController._ensureParticipant(roomId, {
                        userId: designerId,
                        role: 'conception',
                    });
                }
            }

            io.to(roomId).emit('chat_message', msg);

            // --- Notifications Globales ---
            try {
                const participations = await prisma.chatRoomParticipant.findMany({
                    where: { roomId }
                });

                for (const p of participations) {
                    if (p.userId !== userId) {
                        io.to(`global_user_${p.userId}`).emit('new_chat_notification', {
                            roomId,
                            from: from || 'unknown',
                            senderName: senderName || 'Inconnu',
                            text: text || '',
                            attachmentType,
                            timestamp: msg.createdAt
                        });
                    }
                }
            } catch (notifErr) {
                console.error('❌ Erreur lors de l\'envoi de la notification globale:', notifErr.message);
            }

        } catch (err) {
            console.error('❌ Erreur Socket Chat:', err);
        }
    });

    socket.on('delete_message', (data) => {
        if (data.roomId && data.messageId) {
            socket.to(data.roomId).emit('delete_message', data);
        }
    });

    socket.on('typing', (data) => {
        if (data.roomId) {
            socket.to(data.roomId).emit('typing', { roomId: data.roomId, senderName: data.senderName });
        }
    });

    socket.on('stop_typing', (data) => {
        if (data.roomId) {
            socket.to(data.roomId).emit('stop_typing', { roomId: data.roomId });
        }
    });

    socket.on('clear_chat', (data) => {
        if (data.roomId) {
            socket.to(data.roomId).emit('clear_chat', data);
        }
    });

    socket.on('telemetry_data', async (data) => {
        await telemetryController.saveTelemetry(data);
        if (data.power === undefined && data.torque !== undefined && data.rpm !== undefined) {
            data.power = parseFloat(data.torque) * parseFloat(data.rpm);
        }
        io.emit('nouvelle_prediction', data);
    });

    // ─── WebRTC Signaling for Voice/Video Calls ─────────────────────────────
    socket.on('call_initiate', (data) => {
        if (data.roomId) {
            console.log(`📞 Call initiated in room ${data.roomId} by ${data.callerName} (${data.callType})`);
            socket.to(data.roomId).emit('incoming_call', {
                roomId: data.roomId,
                callerId: data.callerId,
                callerName: data.callerName,
                callType: data.callType, // 'voice' or 'video'
            });
        }
    });

    socket.on('call_accept', (data) => {
        if (data.roomId) {
            console.log(`✅ Call accepted in room ${data.roomId}`);
            socket.to(data.roomId).emit('call_accepted', {
                roomId: data.roomId,
                acceptorName: data.acceptorName,
            });
        }
    });

    socket.on('call_reject', (data) => {
        if (data.roomId) {
            console.log(`❌ Call rejected in room ${data.roomId}`);
            socket.to(data.roomId).emit('call_rejected', {
                roomId: data.roomId,
            });
        }
    });

    socket.on('call_end', (data) => {
        if (data.roomId) {
            console.log(`📴 Call ended in room ${data.roomId}`);
            socket.to(data.roomId).emit('call_ended', {
                roomId: data.roomId,
            });
        }
    });

    socket.on('webrtc_offer', (data) => {
        if (data.roomId && data.sdp) {
            socket.to(data.roomId).emit('webrtc_offer', {
                roomId: data.roomId,
                sdp: data.sdp,
            });
        }
    });

    socket.on('webrtc_answer', (data) => {
        if (data.roomId && data.sdp) {
            socket.to(data.roomId).emit('webrtc_answer', {
                roomId: data.roomId,
                sdp: data.sdp,
            });
        }
    });

    socket.on('webrtc_ice_candidate', (data) => {
        if (data.roomId && data.candidate) {
            socket.to(data.roomId).emit('webrtc_ice_candidate', {
                roomId: data.roomId,
                candidate: data.candidate,
            });
        }
    });

    socket.on('disconnect', () => {
        console.log('❌ Client déconnecté:', socket.id);
    });
});

app.use((req, res) => {
    res.status(404).json({
        error: 'Route introuvable',
        path: req.path,
        hint: 'Backend SQL (architecture MVC)',
    });
});

server.listen(PORT, async () => {
    console.log('');
    console.log('==================================================');
    console.log('  DALI PFE — API Node.js + SQL (Prisma, MVC)');
    console.log('==================================================');
    console.log(`  http://localhost:${PORT}`);
    console.log(`  Health : http://localhost:${PORT}/api/health`);
    console.log(`  Socket : http://localhost:${PORT}`);
    console.log(`  Base   : ${process.env.DATABASE_URL ? process.env.DATABASE_URL.split('@')[1] || process.env.DATABASE_URL : '(DATABASE_URL non définie)'}`);
    console.log('==================================================');
    console.log('');

    // Seed admin if not exists
    const adminEmail = process.env.ADMIN_EMAIL;
    if (adminEmail) {
        try {
            const existing = await prisma.user.findUnique({ where: { email: adminEmail.trim().toLowerCase() } });
            if (!existing) {
                const { createUserWithProfile } = require('./lib/auth');
                await createUserWithProfile('admin', {
                    email: adminEmail,
                    nom: process.env.ADMIN_NOM || 'Administrateur DALI',
                    password: process.env.ADMIN_PASSWORD || 'Admin2026!',
                    adresse: 'Tunisie'
                });
                console.log('✅ Admin user created successfully from .env');
            }
        } catch (err) {
            console.error('❌ Failed to seed admin user on startup:', err.message);
        }
    }
});
