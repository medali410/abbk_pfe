// ══════════════════════════════════════════════════════════════════════
//  ABBKA ADMIN - JAVASCRIPT POUR 4 MACHINES SIMULTANÉES
// ══════════════════════════════════════════════════════════════════════

const API = '/api';
let token = localStorage.getItem('token');
let user = JSON.parse(localStorage.getItem('user') || '{}');

// Vérification auth
if (!token || user.role !== 'admin') {
    window.location.href = '/';
}

// Affichage utilisateur
document.getElementById('user-name').textContent = user.nom || user.username;
document.getElementById('current-date').textContent = new Date().toLocaleDateString('fr-FR', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });

// Headers
const headers = () => ({
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`
});

// Données globals
let machinesData = [];
let techniciens = [];
let pannes = [];

// Charts
let comparisonChart = null;
let liveChart = null;
let liveData = {
    labels: [],
    MAC_A01: { temp: [], pressure: [], power: [] },
    MAC_A02: { temp: [], pressure: [], power: [] },
    MAC_A03: { temp: [], pressure: [], power: [] },
    MAC_A04: { temp: [], pressure: [], power: [] }
};
const MAX_DATA_POINTS = 20;

// ══════════════════════════════════════════════════════════════════════
//  INITIALISATION
// ══════════════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    initCharts();
    initModals();
    refreshAll();
    setupMQTT();
});

function initNavigation() {
    const navItems = document.querySelectorAll('.nav-item');
    const pages = document.querySelectorAll('.page');

    navItems.forEach(item => {
        item.addEventListener('click', (e) => {
            e.preventDefault();
            const targetPage = item.getAttribute('data-page');

            navItems.forEach(nav => nav.classList.remove('active'));
            item.classList.add('active');

            pages.forEach(page => {
                page.classList.remove('active');
                if (page.id === `page-${targetPage}`) {
                    page.classList.add('active');
                }
            });

            if (targetPage === 'dashboard') loadStats();
            else if (targetPage === 'machines') loadMachines();
            else if (targetPage === 'techniciens') loadTechniciens();
            else if (targetPage === 'pannes') loadPannes();
        });
    });
}

function refreshAll() {
    loadStats();
    loadMachines();
    loadTechniciens();
    loadPannes();
}

function logout() {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    window.location.href = '/';
}

// ══════════════════════════════════════════════════════════════════════
//  MQTT & WEBSOCKET
// ══════════════════════════════════════════════════════════════════════

function setupMQTT() {
    const statusText = document.getElementById('mqtt-status-text');
    const statusBox = document.getElementById('mqtt-status');

    mqttWS.on('connected', () => {
        statusText.textContent = 'En direct';
        statusBox.classList.add('connected');
    });

    mqttWS.on('disconnected', () => {
        statusText.textContent = 'Déconnecté';
        statusBox.classList.remove('connected');
    });

    mqttWS.on('INITIAL_DATA', (data) => updateDashboard(data));
    mqttWS.on('ALL_MACHINES_UPDATE', (data) => {
        updateDashboard(data);
        updateLiveCharts(data);
        logMQTT(data);
    });

    mqttWS.on('NEW_ALERT', (data) => {
        showNotification(`Alerte sur ${data.machineId}: ${data.message}`);
        loadPannes(); // Rafraîchir
    });

    // Connecter !
    mqttWS.connect();
}

function logMQTT(data) {
    const logBox = document.getElementById('mqtt-log');
    if (!logBox) return;

    const entry = document.createElement('div');
    entry.className = 'log-entry';
    entry.innerHTML = `
        <span class="log-time">[${new Date().toLocaleTimeString()}]</span>
        <span style="color:var(--accent)">Topic:</span> abbk/asus01_9f3a/telemetry 
        <span style="color:var(--green)">Cycle:</span> ${data.factory?.cycle} 
        <span style="color:var(--orange)">Machines:</span> ${data.machines?.length}
    `;

    logBox.prepend(entry);
    if (logBox.children.length > 50) logBox.removeChild(logBox.lastChild);
}

// ══════════════════════════════════════════════════════════════════════
//  DASHBOARD & UPDATES
// ══════════════════════════════════════════════════════════════════════

function updateDashboard(data) {
    if (data.factory) {
        document.getElementById('factory-name').textContent = data.factory.name || 'ABBKA_Factory';
        document.getElementById('factory-cycle').textContent = data.factory.cycle || 0;
        document.getElementById('factory-rssi').textContent = `${data.factory.wifiRssi || 0} dBm`;
        document.getElementById('factory-update').textContent = new Date().toLocaleTimeString();
    }

    if (data.machines && Array.isArray(data.machines)) {
        machinesData = data.machines;

        // Mettre à jour les stats rapides
        let running = 0, warning = 0, critical = 0;
        machinesData.forEach(m => {
            if (m.status === 'RUNNING') running++;
            else if (m.status === 'WARNING') warning++;
            else if (m.status === 'CRITICAL') critical++;
        });

        document.getElementById('stat-running').textContent = running;
        document.getElementById('stat-warning').textContent = warning;
        document.getElementById('stat-critical').textContent = critical;

        // Rendre les grilles
        renderDashboardGrid();
        renderLiveGrid();
        updateComparisonChart();

        // Mettre à jour la table si on est sur l'onglet machines
        if (document.getElementById('page-machines').classList.contains('active')) {
            renderMachinesTable();
        }
    }
}

function renderDashboardGrid() {
    const grid = document.getElementById('machines-4-grid');
    if (!grid) return;

    grid.innerHTML = machinesData.map(m => {
        const met = m.metrics || {};
        const risk = m.prediction?.risk_percent || 0;
        const statusClass = m.status ? m.status.toLowerCase() : 'stopped';

        return `
            <div class="machine-4-card ${statusClass}" onclick="showMachineDetail('${m.machineId}')">
                <div class="machine-4-header">
                    <h3>${m.nom || m.machineId}</h3>
                    <span class="status-badge ${statusClass}">${m.status || 'STOPPED'}</span>
                </div>
                
                <div class="machine-4-metrics">
                    <div class="metric-item">
                        <span class="label">Température</span>
                        <span class="value ${met.thermal > 80 ? 'danger' : ''}">${met.thermal?.toFixed(1) || '--'} °C</span>
                    </div>
                    <div class="metric-item">
                        <span class="label">Pression</span>
                        <span class="value">${met.pressure?.toFixed(1) || '--'} bar</span>
                    </div>
                    <div class="metric-item">
                        <span class="label">Acoustique</span>
                        <span class="value">${met.acoustic?.toFixed(1) || '--'} dB</span>
                    </div>
                    <div class="metric-item">
                        <span class="label">Puissance</span>
                        <span class="value">${met.power?.toFixed(1) || '--'} kW</span>
                    </div>
                </div>
                
                <div class="machine-4-footer">
                    <span class="risk-badge ${risk > 70 ? 'high' : (risk > 40 ? 'medium' : 'low')}">
                        <i class="ri-robot-2-fill"></i> IA: ${risk}%
                    </span>
                    <div class="machine-4-actions" onclick="event.stopPropagation()">
                        ${m.status === 'STOPPED'
                ? `<button class="btn-icon green" onclick="toggleMachine('${m._id}', 'start')" title="Démarrer"><i class="ri-play-fill"></i></button>`
                : `<button class="btn-icon red" onclick="toggleMachine('${m._id}', 'stop')" title="Arrêter"><i class="ri-stop-fill"></i></button>`
            }
                    </div>
                </div>
            </div>
        `;
    }).join('');
}

function renderLiveGrid() {
    const grid = document.getElementById('live-4-grid');
    if (!grid) return;

    grid.innerHTML = machinesData.map(m => {
        const met = m.metrics || {};
        const sec = m.security || {};
        const statusClass = m.status ? m.status.toLowerCase() : 'stopped';

        return `
            <div class="live-machine-card ${sec.state === 'CRITIQUE' ? 'critical' : ''}">
                <div class="live-machine-header">
                    <h3><i class="ri-cpu-line"></i> ${m.nom || m.machineId}</h3>
                    <span class="status-badge ${statusClass}">${m.status || 'OFFLINE'}</span>
                </div>
                
                <div class="live-metrics-grid">
                    <div class="live-metric">
                        <i class="ri-temp-hot-line"></i>
                        <span class="value ${met.thermal > 80 ? 'danger' : ''}">${met.thermal?.toFixed(1) || '0'}</span>
                        <span class="label">°C</span>
                    </div>
                    <div class="live-metric">
                        <i class="ri-dashboard-3-line"></i>
                        <span class="value">${met.pressure?.toFixed(1) || '0'}</span>
                        <span class="label">bar</span>
                    </div>
                    <div class="live-metric">
                        <i class="ri-volume-up-line"></i>
                        <span class="value">${met.acoustic?.toFixed(1) || '0'}</span>
                        <span class="label">dB</span>
                    </div>
                    <div class="live-metric">
                        <i class="ri-flashlight-line"></i>
                        <span class="value">${met.power?.toFixed(0) || '0'}</span>
                        <span class="label">kW</span>
                    </div>
                    <div class="live-metric">
                        <i class="ri-water-flash-line"></i>
                        <span class="value">${met.vibration_x?.toFixed(2) || '0'}</span>
                        <span class="label">Vib X</span>
                    </div>
                    <div class="live-metric">
                        <i class="ri-water-flash-line"></i>
                        <span class="value">${met.vibration_y?.toFixed(2) || '0'}</span>
                        <span class="label">Vib Y</span>
                    </div>
                    <div class="live-metric">
                        <i class="ri-water-flash-line"></i>
                        <span class="value">${met.vibration_z?.toFixed(2) || '0'}</span>
                        <span class="label">Vib Z</span>
                    </div>
                    <div class="live-metric">
                        <i class="ri-drop-line"></i>
                        <span class="value">${met.fluid_flow?.toFixed(1) || '0'}</span>
                        <span class="label">L/min</span>
                    </div>
                </div>
                
                <div class="live-security">
                    <div class="live-security-item">
                        <span>État Sécurité:</span>
                        <span class="${sec.state === 'CRITIQUE' ? 'critical' : 'normal'}">${sec.state || 'INCONNU'}</span>
                    </div>
                    <div class="live-security-item">
                        <span>Alarmes:</span>
                        <span class="${sec.alarms && sec.alarms !== 'Aucune' ? 'critical' : 'normal'}">${sec.alarms || '0'}</span>
                    </div>
                </div>
            </div>
        `;
    }).join('');
}

// ══════════════════════════════════════════════════════════════════════
//  CHARTS
// ══════════════════════════════════════════════════════════════════════

function initCharts() {
    const ctxComp = document.getElementById('comparison-chart');
    if (ctxComp) {
        comparisonChart = new Chart(ctxComp, {
            type: 'bar',
            data: { labels: [], datasets: [] },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: { beginAtZero: true, grid: { color: 'rgba(255,255,255,0.05)' } },
                    x: { grid: { display: false } }
                },
                plugins: {
                    legend: { labels: { color: '#94a3b8' } }
                }
            }
        });
    }

    const ctxLive = document.getElementById('live-chart');
    if (ctxLive) {
        liveChart = new Chart(ctxLive, {
            type: 'line',
            data: { labels: [], datasets: [] },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: false,
                scales: {
                    y: { beginAtZero: false, grid: { color: 'rgba(255,255,255,0.05)' } },
                    x: { grid: { display: false } }
                },
                elements: { point: { radius: 0 } },
                plugins: { legend: { labels: { color: '#94a3b8' } } }
            }
        });
    }
}

function updateComparisonChart() {
    if (!comparisonChart || machinesData.length === 0) return;

    const labels = machinesData.map(m => m.nom || m.machineId);
    const temps = machinesData.map(m => m.metrics?.thermal || 0);
    const powers = machinesData.map(m => m.metrics?.power || 0);
    const risks = machinesData.map(m => m.prediction?.risk_percent || 0);

    comparisonChart.data = {
        labels,
        datasets: [
            { label: 'Température (°C)', data: temps, backgroundColor: '#ef4444' },
            { label: 'Puissance (kW)', data: powers, backgroundColor: '#3b82f6' },
            { label: 'Risque IA (%)', data: risks, backgroundColor: '#8b5cf6' }
        ]
    };
    comparisonChart.update();
}

function updateLiveCharts(data) {
    if (!liveChart || !data.machines) return;

    const now = new Date().toLocaleTimeString();
    liveData.labels.push(now);
    if (liveData.labels.length > MAX_DATA_POINTS) {
        liveData.labels.shift();
    }

    const colors = { MAC_A01: '#3b82f6', MAC_A02: '#10b981', MAC_A03: '#f59e0b', MAC_A04: '#ef4444' };
    const datasets = [];

    data.machines.forEach(m => {
        const id = m.machineId;
        if (!liveData[id]) liveData[id] = { temp: [] };

        liveData[id].temp.push(m.metrics?.thermal || 0);
        if (liveData[id].temp.length > MAX_DATA_POINTS) liveData[id].temp.shift();

        datasets.push({
            label: `${id} Temp`,
            data: liveData[id].temp,
            borderColor: colors[id] || '#ffffff',
            tension: 0.4,
            borderWidth: 2
        });
    });

    liveChart.data = { labels: liveData.labels, datasets };
    liveChart.update();
}

// ══════════════════════════════════════════════════════════════════════
//  A P I  C A L L S
// ══════════════════════════════════════════════════════════════════════

async function loadStats() {
    try {
        const res = await fetch(`${API}/stats`, { headers: headers() });
        const data = await res.json();

        document.getElementById('stat-pannes').textContent = data.pannes?.nouvelles || 0;
        document.getElementById('badge-pannes').textContent = data.pannes?.nouvelles || 0;
        if (data.pannes?.nouvelles > 0) {
            document.getElementById('badge-pannes').style.display = 'block';
        } else {
            document.getElementById('badge-pannes').style.display = 'none';
        }
    } catch (err) { console.error(err); }
}

async function loadMachines() {
    try {
        const res = await fetch(`${API}/machines`, { headers: headers() });
        machinesData = await res.json();
        renderMachinesTable();
    } catch (err) { console.error('Erreur machines:', err); }
}

function renderMachinesTable() {
    const tbody = document.getElementById('machines-table');
    if (!tbody) return;

    tbody.innerHTML = machinesData.map(m => {
        const met = m.metrics || {};
        const risk = m.prediction?.risk_percent || 0;
        const statusClass = m.status ? m.status.toLowerCase() : 'stopped';

        return `
            <tr>
                <td><strong>${m.machineId}</strong></td>
                <td>${m.nom || '-'}</td>
                <td><span class="status-badge ${statusClass}">${m.status || 'STOPPED'}</span></td>
                <td>${met.thermal?.toFixed(1) || '--'} °C</td>
                <td>${met.pressure?.toFixed(1) || '--'} bar</td>
                <td>${met.power?.toFixed(1) || '--'} kW</td>
                <td><span class="${risk > 70 ? 'danger value' : ''}">${risk}%</span></td>
                <td>${m.security?.state || '-'}</td>
                <td>
                    <button class="btn-small" onclick="showMachineDetail('${m.machineId}')"><i class="ri-eye-line"></i></button>
                    <button class="btn-small red" onclick="deleteMachine('${m._id}')"><i class="ri-delete-bin-line"></i></button>
                </td>
            </tr>
        `;
    }).join('');
}

async function toggleMachine(id, action) {
    try {
        await fetch(`${API}/machines/${id}/${action}`, { method: 'POST', headers: headers() });
        loadMachines();
    } catch (err) { alert('Erreur'); }
}

async function deleteMachine(id) {
    if (!confirm("Supprimer cette machine ?")) return;
    try {
        await fetch(`${API}/machines/${id}`, { method: 'DELETE', headers: headers() });
        loadMachines();
    } catch (err) { alert('Erreur'); }
}

// ══════════════════════════════════════════════════════════════════════
//  TECHNICIENS & PANNES
// ══════════════════════════════════════════════════════════════════════

async function loadTechniciens() {
    try {
        const res = await fetch(`${API}/techniciens`, { headers: headers() });
        techniciens = await res.json();

        const grid = document.getElementById('techs-grid');
        const select = document.getElementById('a-tech');
        if (!grid) return;

        grid.innerHTML = techniciens.map(t => `
            <div class="tech-card">
                <div class="avatar">👷</div>
                <div class="info">
                    <h4>${t.nom}</h4>
                    <p>@${t.username}</p>
                    <p><i class="ri-mail-line"></i> ${t.email || '-'}</p>
                </div>
                <button class="btn-icon red" onclick="deleteTech('${t._id}')"><i class="ri-delete-bin-line"></i></button>
            </div>
        `).join('');

        if (select) {
            select.innerHTML = techniciens.map(t => `<option value="${t._id}">${t.nom}</option>`).join('');
        }
    } catch (err) { console.error(err); }
}

async function deleteTech(id) {
    if (!confirm("Supprimer ce technicien ?")) return;
    try {
        await fetch(`${API}/techniciens/${id}`, { method: 'DELETE', headers: headers() });
        loadTechniciens();
    } catch (err) { alert('Erreur'); }
}

async function loadPannes() {
    try {
        const res = await fetch(`${API}/pannes`, { headers: headers() });
        pannes = await res.json();
        renderPannes('all');
    } catch (err) { console.error('Erreur pannes', err); }
}

function filterPannes(status) {
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    event.target.classList.add('active');
    renderPannes(status);
}

function renderPannes(filter) {
    const list = document.getElementById('pannes-list');
    if (!list) return;

    let filtered = pannes;
    if (filter !== 'all') filtered = pannes.filter(p => p.status === filter);

    list.innerHTML = filtered.map(p => `
        <div class="panne-card ${p.status}">
            <div class="panne-header">
                <h4><i class="ri-tools-fill"></i> Machine: ${p.machineId}</h4>
                <span class="status-badge ${p.status}">${p.status}</span>
            </div>
            <div class="panne-content">
                <p><strong>Type:</strong> ${p.type} | <strong>Sévérité:</strong> ${p.severity}</p>
                <p>${p.description || 'Aucune description'}</p>
                ${p.technicienNom ? `<p><strong>Assigné à:</strong> ${p.technicienNom}</p>` : ''}
            </div>
            <div class="panne-footer">
                <span class="date">${new Date(p.createdAt).toLocaleString()}</span>
                ${p.status === 'NOUVELLE' ? `
                    <button class="btn-small" onclick="openAssignModal('${p._id}')">Assigner</button>
                ` : p.status === 'TERMINEE' ? `
                    <button class="btn-small green" onclick="alert('Rapport: ${p.rapport}')">Voir Rapport</button>
                ` : ''}
            </div>
        </div>
    `).join('');
}

function openAssignModal(id) {
    document.getElementById('a-panne-id').value = id;
    openModal('assign');
}

// ══════════════════════════════════════════════════════════════════════
//  MODALS
// ══════════════════════════════════════════════════════════════════════

function openModal(id) {
    document.getElementById(`modal-${id}`).classList.add('active');
    if (id === 'panne') {
        document.getElementById('p-machine').innerHTML = machinesData.map(m => `<option value="${m.machineId}">${m.machineId} - ${m.nom || ''}</option>`).join('');
    }
}

function closeModal(id) {
    document.getElementById(`modal-${id}`).classList.remove('active');
}

function showNotification(msg) {
    // Simple alert pour l'instant
    console.log("NOTIF:", msg);
}

function showMachineDetail(machineId) {
    const m = machinesData.find(x => x.machineId === machineId);
    if (!m) return;

    const root = document.getElementById('detail-content');
    document.getElementById('detail-title').textContent = `Détails - ${m.machineId}`;

    root.innerHTML = `<pre style="background:#0f172a; padding:15px; border-radius:8px; overflow:auto;">${JSON.stringify(m, null, 2)}</pre>`;
    openModal('detail');
}

// ══════════════════════════════════════════════════════════════════════
//  SOUMISSION FORMULAIRES
// ══════════════════════════════════════════════════════════════════════

document.getElementById('form-machine')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const data = {
        machineId: document.getElementById('m-id').value,
        nom: document.getElementById('m-nom').value,
        localisation: document.getElementById('m-loc').value
    };
    try {
        await fetch(`${API}/machines`, { method: 'POST', headers: headers(), body: JSON.stringify(data) });
        closeModal('machine');
        loadMachines();
    } catch (err) { alert('Erreur'); }
});

document.getElementById('form-tech')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const data = {
        nom: document.getElementById('t-nom').value,
        username: document.getElementById('t-user').value,
        password: document.getElementById('t-pass').value,
        email: document.getElementById('t-email').value
    };
    try {
        await fetch(`${API}/techniciens`, { method: 'POST', headers: headers(), body: JSON.stringify(data) });
        closeModal('tech');
        e.target.reset();
        loadTechniciens();
    } catch (err) { alert('Erreur'); }
});

document.getElementById('form-panne')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const data = {
        machineId: document.getElementById('p-machine').value,
        type: document.getElementById('p-type').value,
        severity: document.getElementById('p-severity').value,
        description: document.getElementById('p-desc').value
    };
    try {
        await fetch(`${API}/pannes`, { method: 'POST', headers: headers(), body: JSON.stringify(data) });
        closeModal('panne');
        e.target.reset();
        loadPannes();
        loadStats();
    } catch (err) { alert('Erreur'); }
});

document.getElementById('form-assign')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const id = document.getElementById('a-panne-id').value;
    const data = {
        technicienId: document.getElementById('a-tech').value,
        message: document.getElementById('a-msg').value
    };
    try {
        await fetch(`${API}/pannes/${id}/assign`, { method: 'POST', headers: headers(), body: JSON.stringify(data) });
        closeModal('assign');
        e.target.reset();
        loadPannes();
    } catch (err) { alert('Erreur'); }
});
