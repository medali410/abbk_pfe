// src/index.js  (version mise à jour — intègre les nouvelles routes)
// ─── Seules les lignes modifiées/ajoutées sont marquées [AJOUT] ──────────────

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');

const authRoutes             = require('./routes/auth');
const clientsRoutes          = require('./routes/clients');
const machinesRoutes         = require('./routes/machines');
const dashboardRoutes        = require('./routes/dashboard');
const actorsRoutes           = require('./routes/actors');
const documentsRoutes        = require('./routes/documents');
const telemetryRoutes        = require('./routes/telemetry');
const chatRoutes             = require('./routes/chat');
const purchaseRequestsRoutes = require('./routes/purchaseRequests');

// [AJOUT] Nouvelles routes dédiées Technicien et Agent de Maintenance
const techniciansRoutes      = require('./routes/technicians');        // [AJOUT]
const maintenanceAgentsRoutes = require('./routes/maintenanceAgents'); // [AJOUT]
const controlesRoutes        = require('./routes/controles');          // [AJOUT]
const maintenanceOrdersRoutes = require('./routes/maintenanceOrders'); // [AJOUT]
const consultationRoutes     = require('./routes/consultations');
const notificationRoutes     = require('./routes/notifications');
const missionRoutes          = require('./routes/missions');

const healthController    = require('./controllers/healthController');
const telemetryController = require('./controllers/telemetryController');
const { prisma }          = require('./lib/prisma');

const PORT = parseInt(String(process.env.PORT || '3001'), 10);
const app  = express();
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

// ─── Routes ───────────────────────────────────────────────────────────────────
app.use('/api',                          authRoutes);
app.use('/api/clients',                  clientsRoutes);
app.use('/api/machines',                 machinesRoutes);
app.use('/api/dashboard',               dashboardRoutes);
app.use('/api',                          actorsRoutes);            // garde la compatibilité avec /api/concepteurs
app.use('/api/conceptions',             documentsRoutes);
app.use('/api/documents',               documentsRoutes);
app.use('/api',                          telemetryRoutes);
app.use('/api/chat',                     chatRoutes);
app.use('/api/purchase-requests',        purchaseRequestsRoutes);

// [AJOUT] Routes dédiées Technicien et Agent de Maintenance
app.use('/api/technicians',              techniciansRoutes);        // [AJOUT]
app.use('/api/maintenance-agents',       maintenanceAgentsRoutes);  // [AJOUT]
app.use('/api/controles',                controlesRoutes);          // [AJOUT]
app.use('/api/maintenance-orders',       maintenanceOrdersRoutes);  // [AJOUT]
app.use('/api/consultations',            consultationRoutes);
app.use('/api/notifications',            notificationRoutes);
app.use('/api/missions',                 missionRoutes);

// ─── Socket.io ────────────────────────────────────────────────────────────────
const chatController = require('./controllers/chatController');

io.on('connection', (socket) => {
    console.log('🔌 Client connecté via Socket.io:', socket.id);

    socket.on('join_chat_room', (data) => {
        if (data.roomId) {
            socket.join(data.roomId);
            console.log(`💬 Socket ${socket.id} a rejoint la salle : ${data.roomId}`);
        }
    });

    socket.on('chat_message', async (data) => {
        try {
            const { roomId, from, senderName, text, userId, attachmentUrl, attachmentType } = data;
            if (!roomId || (!text && !attachmentUrl)) return;

            await prisma.chatRoom.upsert({
                where:  { roomId },
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
        } catch (err) {
            console.error('❌ Erreur Socket Chat:', err);
        }
    });

    socket.on('delete_message', (data) => {
        if (data.roomId && data.messageId) {
            socket.to(data.roomId).emit('delete_message', data);
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

server.listen(PORT, () => {
    console.log('');
    console.log('==================================================');
    console.log('  DALI PFE — API Node.js + SQL (Prisma, MVC)');
    console.log('==================================================');
    console.log(`  http://localhost:${PORT}`);
    console.log(`  Health : http://localhost:${PORT}/api/health`);
    console.log(`  Socket : http://localhost:${PORT}`);
    console.log(`  Base   : ${process.env.DATABASE_URL.split('@')[1] || '(DATABASE_URL)'}`);
    console.log('==================================================');
    console.log('');
});
