// ══════════════════════════════════════════════════════════════════════
//  CLIENT WEBSOCKET POUR MQTT TEMPS RÉEL
// ══════════════════════════════════════════════════════════════════════

class MQTTWebSocketClient {
    constructor() {
        this.ws = null;
        this.listeners = {};
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 10;
    }

    connect() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}`;

        console.log('🔌 Connexion WebSocket:', wsUrl);
        this.ws = new WebSocket(wsUrl);

        this.ws.onopen = () => {
            console.log('✅ WebSocket connecté');
            this.reconnectAttempts = 0;
            this.emit('connected');
        };

        this.ws.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                console.log('📡 Message:', data.type);
                this.emit(data.type, data);
                this.emit('message', data);
            } catch (err) {
                console.error('Erreur parse:', err);
            }
        };

        this.ws.onclose = () => {
            console.log('🔌 WebSocket déconnecté');
            this.emit('disconnected');

            if (this.reconnectAttempts < this.maxReconnectAttempts) {
                this.reconnectAttempts++;
                console.log(`🔄 Reconnexion ${this.reconnectAttempts}...`);
                setTimeout(() => this.connect(), 2000);
            }
        };

        this.ws.onerror = (err) => {
            console.error('❌ Erreur WebSocket:', err);
            this.emit('error', err);
        };
    }

    on(event, callback) {
        if (!this.listeners[event]) this.listeners[event] = [];
        this.listeners[event].push(callback);
    }

    emit(event, data) {
        if (this.listeners[event]) {
            this.listeners[event].forEach(cb => cb(data));
        }
    }

    disconnect() {
        if (this.ws) this.ws.close();
    }
}

const mqttWS = new MQTTWebSocketClient();
