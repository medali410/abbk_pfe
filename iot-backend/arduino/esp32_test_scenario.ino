/*
 * ================================================================
 *  DALI PFE - SCÉNARIO DE TEST : DÉTECTION PANNE PAR IA
 * ================================================================
 *
 *  PHASE 1 (0:00 - 1:00)  : NORMAL STABLE
 *     Température fixe ~45°C, tout est OK
 *
 *  PHASE 2 (1:00 - 2:30)  : DÉGRADATION LENTE
 *     Température monte : 55°C → 70°C → 85°C → 95°C
 *     L'IA doit détecter le problème AVANT la panne
 *
 *  PHASE 3 (2:30 - 3:30)  : PANNE CRITIQUE
 *     Température > 100°C, vibrations extrêmes
 *     L'IA doit recommander l'arrêt
 *
 *  Puis retour au normal et nouveau cycle
 *
 *  ENVOI : toutes les 3 secondes via MQTT
 * ================================================================
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <math.h>

// ===================== CONFIG =====================

const char* MACHINE_ID  = "MAC-1775750118162";
const char* MOTOR_TYPE  = "triphase";
const char* COMPANY_ID  = "CLI-2026-619";

const char* WIFI_SSID   = "TT_CD81";
const char* WIFI_PASS   = "Oussema1988@";

const char* SERVER_IP   = "192.168.1.16";
const int   SERVER_PORT = 3001;

const char* MQTT_BROKER = "broker.hivemq.com";
const int   MQTT_PORT   = 1883;

// ===================== TIMING =====================

const unsigned long PHASE_NORMAL  = 60000;    // 1 min normal
const unsigned long PHASE_DEGRAD  = 90000;    // 1.5 min dégradation
const unsigned long PHASE_PANNE   = 60000;    // 1 min panne
const unsigned long TOTAL_CYCLE   = PHASE_NORMAL + PHASE_DEGRAD + PHASE_PANNE;
const unsigned long SEND_INTERVAL = 3000;     // 3 sec

// ===================== STRUCT =====================

typedef struct {
    float temperature;
    float pression;
    float puissance;
    float vibration;
    float presence;
    float magnetique;
    float infrarouge;
    float ultrasonic;
} SensorData;

// ===================== VARIABLES =====================

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);

unsigned long lastSend = 0;
unsigned long cycleStart = 0;
int currentPhase = -1;

float randF(float lo, float hi) {
    return lo + (float)random(0, 10000) / 10000.0f * (hi - lo);
}

// ===================== PHASE 1 : NORMAL (1 min) =====================
// Température stable ~45°C, moteur sain

SensorData genNormal() {
    SensorData v;
    v.temperature = randF(42.0, 48.0);
    v.pression    = randF(0.02, 0.035);
    v.puissance   = randF(58000, 65000);
    v.vibration   = randF(0.4, 1.0);
    v.presence    = 1.0;
    v.magnetique  = randF(0.4, 0.6);
    v.infrarouge  = v.temperature + randF(-1.0, 2.0);
    v.ultrasonic  = randF(27.0, 32.0);
    return v;
}

// ===================== PHASE 2 : DÉGRADATION (1.5 min) =====================
// p va de 0.0 à 1.0
// Temp: 55°C → 95°C progressivement

SensorData genDegradation(float p) {
    SensorData v;

    v.temperature = 55.0 + p * 40.0 + randF(-1.5, 1.5);
    v.temperature += sin(p * 8.0) * 2.0;

    v.pression  = 0.03 + p * 0.04 + randF(-0.005, 0.005);
    v.puissance = 65000 + p * 50000 + randF(-4000, 4000);
    v.vibration = 1.0 + p * 3.5 + randF(-0.2, 0.3);

    if (p > 0.4 && random(0, 100) < 25) v.vibration += randF(0.8, 1.5);
    if (p > 0.7) v.puissance += randF(-8000, 12000);

    v.presence   = 1.0;
    v.magnetique = 0.5 + p * 0.3 + randF(-0.04, 0.04);
    v.infrarouge = v.temperature + randF(2.0, 10.0);
    v.ultrasonic = 30.0 + p * 18.0 + randF(-2.0, 2.0);
    return v;
}

// ===================== PHASE 3 : PANNE (1 min) =====================
// Temp: 95°C → 130°C, vibrations extrêmes

SensorData genPanne(float p) {
    SensorData v;

    v.temperature = 95.0 + p * 35.0 + randF(-3.0, 4.0);
    v.temperature += sin(p * 12.0) * 4.0;

    v.pression  = 0.07 + p * 0.06 + sin(p * 18.0) * 0.02;
    if (v.pression < 0.01) v.pression = 0.01;

    v.puissance = 140000 + p * 50000 + randF(-15000, 18000);
    v.vibration = 4.5 + p * 4.5 + randF(-0.5, 1.0);

    v.presence   = 1.0;
    v.magnetique = 0.8 + p * 0.15 + randF(-0.04, 0.04);
    v.infrarouge = v.temperature + randF(10.0, 25.0);
    v.ultrasonic = 48.0 + p * 22.0 + randF(-4.0, 4.0);
    return v;
}

// ===================== WIFI =====================

void connectWiFi() {
    Serial.print("WiFi...");
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    int n = 0;
    while (WiFi.status() != WL_CONNECTED && n < 40) {
        delay(500);
        Serial.print(".");
        n++;
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.print(" OK! IP=");
        Serial.println(WiFi.localIP());
    } else {
        Serial.println(" ECHEC! Redemarrage...");
        delay(5000);
        ESP.restart();
    }
}

// ===================== MQTT =====================

void onMessage(char* topic, byte* payload, unsigned int len) {
    String msg;
    for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
    Serial.printf("[RECV] %s: %s\n", topic, msg.c_str());
}

void connectMQTT() {
    mqtt.setServer(MQTT_BROKER, MQTT_PORT);
    mqtt.setCallback(onMessage);
    char id[32];
    snprintf(id, sizeof(id), "esp32_%s_%d", MACHINE_ID, random(1000, 9999));
    if (mqtt.connect(id)) {
        Serial.println("MQTT OK!");
        char t1[64], t2[64];
        snprintf(t1, sizeof(t1), "machines/%s/control", MACHINE_ID);
        snprintf(t2, sizeof(t2), "machines/%s/cmd", MACHINE_ID);
        mqtt.subscribe(t1);
        mqtt.subscribe(t2);
    } else {
        Serial.printf("MQTT echec (rc=%d)\n", mqtt.state());
    }
}

// ===================== ENVOI =====================

void envoyerDonnees(SensorData v, const char* phase) {
    StaticJsonDocument<512> doc;
    doc["machineId"]   = MACHINE_ID;
    doc["type_moteur"] = MOTOR_TYPE;
    doc["temperature"] = round(v.temperature * 10) / 10.0;
    doc["pressure"]    = round(v.pression * 1000) / 1000.0;
    doc["power"]       = round(v.puissance);
    doc["vibration"]   = round(v.vibration * 100) / 100.0;
    doc["presence"]    = (int)v.presence;
    doc["magnetic"]    = round(v.magnetique * 100) / 100.0;
    doc["infrared"]    = round(v.infrarouge * 10) / 10.0;
    doc["ultrasonic"]  = round(v.ultrasonic * 10) / 10.0;
    doc["rpm"]         = 1500;
    doc["torque"]      = 40.0;

    char body[512];
    serializeJson(doc, body, sizeof(body));

    char topic[64];
    snprintf(topic, sizeof(topic), "machines/%s/telemetry", MACHINE_ID);
    mqtt.publish(topic, body);
    mqtt.publish("test/machines", body);

    unsigned long elapsed = (millis() - cycleStart) / 1000;
    int minutes = elapsed / 60;
    int seconds = elapsed % 60;

    Serial.printf("[%02d:%02d] %-12s | Temp=%.1fC  Vib=%.2f  Puis=%.0fkW  Pres=%.3f\n",
                  minutes, seconds, phase,
                  v.temperature, v.vibration, v.puissance, v.pression);
}

// ===================== SETUP =====================

void setup() {
    Serial.begin(115200);
    randomSeed(analogRead(0) + micros());

    Serial.println("\n================================================");
    Serial.println("  DALI PFE - TEST DETECTION PANNE PAR IA");
    Serial.println("================================================");
    Serial.printf("  Machine : %s (dzli / expresse)\n", MACHINE_ID);
    Serial.printf("  Type    : %s\n", MOTOR_TYPE);
    Serial.println("================================================");
    Serial.println("  PHASE 1 : 0:00-1:00  NORMAL STABLE (~45C)");
    Serial.println("  PHASE 2 : 1:00-2:30  DEGRADATION (55->95C)");
    Serial.println("  PHASE 3 : 2:30-3:30  PANNE CRITIQUE (>100C)");
    Serial.println("================================================\n");

    connectWiFi();
    connectMQTT();

    cycleStart = millis();
    Serial.println("\n>>> PHASE 1 : NORMAL STABLE <<<\n");
}

// ===================== LOOP =====================

void loop() {
    if (WiFi.status() != WL_CONNECTED) connectWiFi();
    if (!mqtt.connected()) connectMQTT();
    mqtt.loop();

    unsigned long now = millis();
    unsigned long elapsed = now - cycleStart;

    int phase;
    float progress;
    const char* phaseName;

    if (elapsed < PHASE_NORMAL) {
        phase = 0;
        progress = (float)elapsed / (float)PHASE_NORMAL;
        phaseName = "NORMAL";
    }
    else if (elapsed < PHASE_NORMAL + PHASE_DEGRAD) {
        phase = 1;
        progress = (float)(elapsed - PHASE_NORMAL) / (float)PHASE_DEGRAD;
        phaseName = "DEGRADATION";
    }
    else if (elapsed < TOTAL_CYCLE) {
        phase = 2;
        progress = (float)(elapsed - PHASE_NORMAL - PHASE_DEGRAD) / (float)PHASE_PANNE;
        phaseName = "PANNE";
    }
    else {
        cycleStart = now;
        currentPhase = -1;
        Serial.println("\n========================================");
        Serial.println("  CYCLE TERMINE - Redemarrage du test");
        Serial.println("========================================\n");
        Serial.println(">>> PHASE 1 : NORMAL STABLE <<<\n");
        return;
    }

    if (phase != currentPhase) {
        currentPhase = phase;
        Serial.println();
        if (phase == 0) {
            Serial.println(">>> PHASE 1 : NORMAL STABLE <<<");
            Serial.println("    Temp: 42-48C | Vib: 0.4-1.0\n");
        } else if (phase == 1) {
            Serial.println("!!! PHASE 2 : DEGRADATION - Temperature monte !!!");
            Serial.println("    Temp: 55->95C | Vib: 1.0->4.5");
            Serial.println("    >>> L'IA DOIT DETECTER ICI <<<\n");
        } else {
            Serial.println("XXX PHASE 3 : PANNE CRITIQUE XXX");
            Serial.println("    Temp: 95->130C | Vib: 4.5->9.0");
            Serial.println("    >>> ARRET MOTEUR RECOMMANDE <<<\n");
        }
    }

    if (now - lastSend >= SEND_INTERVAL) {
        lastSend = now;

        SensorData v;
        if (phase == 0)      v = genNormal();
        else if (phase == 1) v = genDegradation(progress);
        else                 v = genPanne(progress);

        envoyerDonnees(v, phaseName);
    }
}
