const express = require('express');
const path = require('path');

const app = express();
const PORT = 8080;

// Servir les fichiers statiques du dossier public
app.use(express.static(path.join(__dirname, 'public')));

// Routes pour les pages principales
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/admin', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

app.get('/technicien', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'technicien.html'));
});

app.listen(PORT, () => {
    console.log(`
╔════════════════════════════════════════════════╗
║   🌐 ABBKA - APP WEB (FRONTEND)               ║
║                                                ║
║   URL: http://localhost:${PORT}                  ║
║   API: http://localhost:3000/api              ║
╚════════════════════════════════════════════════╝
  `);
});
