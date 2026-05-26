require('dotenv').config();
const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');

const authRoutes = require('./routes/auth');
const clientsRoutes = require('./routes/clients');
const machinesRoutes = require('./routes/machines');
const dashboardRoutes = require('./routes/dashboard');
const actorsRoutes = require('./routes/actors');
const documentsRoutes = require('./routes/documents');
const telemetryRoutes = require('./routes/telemetry');
const chatRoutes = require('./routes/chat');
const healthController = require('./controllers/healthController');
const telemetryController = require('./controllers/telemetryController');
const { prisma } = require('./lib/prisma');

const PORT = parseInt(String(process.env.PORT || '3001'), 10);
const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: true,
        credentials: true,
    }
});

app.use(
    cors({
        origin: true,
        credentials: true,
    }),
);
app.use(express.json({ limit: '50mb' }));

// Serve static uploads
const path = require('path');
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

// Health check
app.get('/api/health', healthController.check);

// API Routes
app.use('/api', authRoutes);
app.use('/api/clients', clientsRoutes);
app.use('/api/machines', machinesRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api', actorsRoutes);
app.use('/api/conceptions', documentsRoutes);
app.use('/api/documents', documentsRoutes);
app.use('/api', telemetryRoutes);
app.use('/api/chat', chatRoutes);

const chatController = require('./controllers/chatController');

// Socket.io logic
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

            // Ensure room exists
            await prisma.chatRoom.upsert({
                where: { roomId },
                create: { roomId },
                update: { updatedAt: new Date() },
            });

            // Save message to database
            await prisma.chatMessage.create({
                data: {
                    roomId,
                    from,
                    senderName,
                    text: text || '',
                    attachmentUrl,
                    attachmentType,
                }
            });

            // Track participant (best-effort)
            if (userId) {
                await chatController._ensureParticipant(roomId, {
                    userId,
                    role: from || 'unknown',
                    userName: senderName || '',
                });
            }

            // Broadcast to room
            socket.to(roomId).emit('chat_message', data);
        } catch (err) {
            console.error('❌ Erreur Socket Chat:', err);
        }
    });

    // Réception des données de télémétrie
    socket.on('telemetry_data', async (data) => {
        await telemetryController.saveTelemetry(data);
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
