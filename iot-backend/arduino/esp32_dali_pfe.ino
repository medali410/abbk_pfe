/*
 * ================================================================
 *  DALI PFE - ESP32 Simulateur (SANS capteurs reels)
 * ================================================================
 *
 *  Pas de cablage ! L'ESP32 genere des valeurs virtuelles
 *  pour tester l'affichage du dashboard et le modele IA.
 *
 *  Cycle :
 *    5 min NORMAL -> 5 min SURCHAUFFE -> 5 min NORMAL -> 5 min ROULEMENT
 *    -> 5 min NORMAL -> 5 min SURCHARGE -> 5 min NORMAL -> 5 min ELECTRIQUE
 *    -> 5 min NORMAL -> 5 min USURE -> 5 min NORMAL -> 5 min PRESSION
 *    -> recommence...
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <math.h>

// ===================== A MODIFIER =====================

const char* MACHINE_ID  = "MAC-1775750118162";  // machine "dzli"
const char* MOTOR_TYPE  = "triphase";
const char* COMPANY_ID  = "CLI-2026-619";

const char* WIFI_SSID   = "";                // <<< METTRE TON NOM WIFI ICI
const char* WIFI_PASS   = "";                // <<< METTRE TON MOT DE PASSE WIFI ICI

const char* SERVER_IP   = "192.168.1.16";    // IP de ton PC
const int   SERVER_PORT = 3001;

const char* MQTT_BROKER = "broker.hivemq.com";
const int   MQTT_PORT   = 1883;

// ===================== TIMING =====================

const unsigned long SCENARIO_DURATION = 300000;  // 5 minutes
const unsigned long SEND_INTERVAL     = 3000;    // 3 secondes

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

// ===================== SCENARIOS =====================

const int SC_NORMAL     = 0;
const int SC_SURCHAUFFE = 1;
const int SC_ROULEMENT  = 2;
const int SC_SURCHARGE  = 3;
const int SC_ELECTRIQUE = 4;
const int SC_USURE      = 5;
const int SC_PRESSION   = 6;

const char* SCENARIO_NAMES[] = {
    "NORMAL", "SURCHAUFFE", "ROULEMENT",
    "SURCHARGE", "ELECTRIQUE", "USURE_GENERALE", "PRESSION"
};

int SEQUENCE[] = {
    SC_NORMAL, SC_SURCHAUFFE,
    SC_NORMAL, SC_ROULEMENT,
    SC_NORMAL, SC_SURCHARGE,
    SC_NORMAL, SC_ELECTRIQUE,
    SC_NORMAL, SC_USURE,
    SC_NORMAL, SC_PRESSION
};
const int SEQ_LEN = 12;

// ===================== VARIABLES =====================

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);

unsigned long lastSend = 0;
unsigned long phaseStart = 0;
int currentPhase = 0;

// ===================== RANDOM =====================

float randF(float lo, float hi) {
    return lo + (float)random(0, 10000) / 10000.0f * (hi - lo);
}

// ===================== GENERATION VALEURS =====================

SensorData valeurNormale() {
    SensorData v;
    v.temperature = randF(35.0, 55.0);
    v.pression    = randF(0.02, 0.04);
    v.puissance   = randF(50000, 70000);
    v.vibration   = randF(0.5, 1.5);
    v.presence    = 1.0;
    v.magnetique  = randF(0.4, 0.7);
    v.infrarouge  = v.temperature + randF(-3.0, 5.0);
    v.ultrasonic  = randF(25.0, 50.0);
    return v;
}

SensorData valeurSurchauffe(float p) {
    SensorData v;
    v.temperature = 60.0 + p * 60.0 + randF(-3, 3);
    if (p > 0.3) v.temperature += sin(p * 20.0) * 8.0;
    v.pression    = randF(0.03, 0.06);
    v.puissance   = randF(80000, 130000);
    v.vibration   = 1.5 + p * 2.0 + randF(-0.3, 0.3);
    v.presence    = 1.0;
    v.magnetique  = randF(0.5, 0.8);
    v.infrarouge  = v.temperature + randF(5.0, 20.0);
    v.ultrasonic  = randF(20.0, 55.0);
    return v;
}

SensorData valeurRoulement(float p) {
    SensorData v;
    v.temperature = 50.0 + p * 25.0 + randF(-2, 2);
    v.pression    = randF(0.02, 0.04);
    v.puissance   = randF(55000, 85000);
    v.vibration   = 3.0 + p * 5.0 + randF(-0.5, 0.5);
    if (random(0, 100) < 30) v.vibration += randF(2.0, 4.0);
    v.presence    = 1.0;
    v.magnetique  = randF(0.3, 0.7);
    v.infrarouge  = v.temperature + randF(0.0, 8.0);
    v.ultrasonic  = randF(15.0, 70.0);
    return v;
}

SensorData valeurSurcharge(float p) {
    SensorData v;
    v.temperature = 55.0 + p * 30.0 + randF(-2, 2);
    v.pression    = 0.05 + p * 0.08 + randF(-0.01, 0.01);
    v.puissance   = 120000 + p * 80000 + randF(-5000, 5000);
    v.vibration   = 2.0 + p * 2.5 + randF(-0.3, 0.3);
    v.presence    = 1.0;
    v.magnetique  = randF(0.6, 0.95);
    v.infrarouge  = v.temperature + randF(3.0, 10.0);
    v.ultrasonic  = randF(20.0, 55.0);
    return v;
}

SensorData valeurElectrique(float p) {
    SensorData v;
    v.temperature = 45.0 + p * 40.0 + randF(-5, 5);
    v.pression    = randF(0.01, 0.03);
    v.puissance   = (random(0, 100) < 40) ? randF(10000, 30000) : randF(100000, 170000);
    v.vibration   = randF(1.0, 3.0);
    v.presence    = (random(0, 100) < 20) ? 0.0 : 1.0;
    v.magnetique  = (random(0, 100) < 50) ? randF(0.05, 0.15) : randF(0.85, 0.98);
    v.infrarouge  = v.temperature + randF(-10.0, 20.0);
    v.ultrasonic  = randF(20.0, 60.0);
    return v;
}

SensorData valeurUsure(float p) {
    SensorData v;
    v.temperature = 50.0 + p * 20.0 + randF(-3, 3);
    v.pression    = 0.03 + p * 0.04 + randF(-0.005, 0.005);
    v.puissance   = 60000 - p * 20000 + randF(-3000, 3000);
    v.vibration   = 2.0 + p * 3.5 + randF(-0.5, 0.5);
    v.presence    = 1.0;
    v.magnetique  = 0.5 - p * 0.3 + randF(-0.05, 0.05);
    v.infrarouge  = v.temperature + randF(0.0, 10.0);
    v.ultrasonic  = randF(20.0, 55.0);
    return v;
}

SensorData valeurPression(float p) {
    SensorData v;
    v.temperature = 55.0 + p * 15.0 + randF(-2, 2);
    v.pression    = 0.04 + sin(p * 15.0) * 0.05 + randF(-0.01, 0.01);
    if (v.pression < 0.005) v.pression = 0.005;
    v.puissance   = randF(60000, 90000);
    v.vibration   = 1.5 + p * 1.5 + randF(-0.3, 0.3);
    v.presence    = 1.0;
    v.magnetique  = randF(0.4, 0.7);
    v.infrarouge  = v.temperature + randF(0.0, 5.0);
    v.ultrasonic  = randF(20.0, 55.0);
    return v;
}

SensorData genererValeurs(int scenario, float p) {
    switch (scenario) {
        case SC_SURCHAUFFE: return valeurSurchauffe(p);
        case SC_ROULEMENT:  return valeurRoulement(p);
        case SC_SURCHARGE:  return valeurSurcharge(p);
        case SC_ELECTRIQUE: return valeurElectrique(p);
        case SC_USURE:      return valeurUsure(p);
        case SC_PRESSION:   return valeurPression(p);
        default:            return valeurNormale();
    }
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

void envoyerDonnees(SensorData v, int scenario) {
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

    Serial.printf("[%s] %s | T=%.1f V=%.1f P=%.0f Mag=%.2f\n",
                  MACHINE_ID, SCENARIO_NAMES[scenario],
                  v.temperature, v.vibration, v.puissance, v.magnetique);
}

// ===================== SETUP =====================

void setup() {
    Serial.begin(115200);
    randomSeed(analogRead(0) + micros());

    Serial.println("\n============================================");
    Serial.println("  DALI PFE - ESP32 SIMULATEUR (sans capteurs)");
    Serial.printf("  Machine : %s\n", MACHINE_ID);
    Serial.printf("  Type    : %s\n", MOTOR_TYPE);
    Serial.println("============================================");
    Serial.println("  Valeurs virtuelles - pas de cablage");
    Serial.println("  5min Normal -> 5min Panne (6 types)");
    Serial.println("============================================\n");

    if (strlen(MACHINE_ID) == 0) {
        Serial.println("!! ERREUR: MACHINE_ID est vide !!");
        Serial.println("!! Modifiez la ligne 24 du code !!");
        while (true) { delay(1000); }
    }

    connectWiFi();
    connectMQTT();

    phaseStart = millis();
    currentPhase = 0;
    Serial.printf("\n>>> PHASE 1/%d : %s <<<\n\n", SEQ_LEN, SCENARIO_NAMES[SEQUENCE[0]]);
}

// ===================== LOOP =====================

void loop() {
    if (WiFi.status() != WL_CONNECTED) connectWiFi();
    if (!mqtt.connected()) connectMQTT();
    mqtt.loop();

    unsigned long now = millis();

    if (now - phaseStart >= SCENARIO_DURATION) {
        phaseStart = now;
        currentPhase = (currentPhase + 1) % SEQ_LEN;
        Serial.printf("\n>>> PHASE %d/%d : %s <<<\n\n",
                      currentPhase + 1, SEQ_LEN, SCENARIO_NAMES[SEQUENCE[currentPhase]]);
    }

    if (now - lastSend >= SEND_INTERVAL) {
        lastSend = now;
        float progress = (float)(now - phaseStart) / (float)SCENARIO_DURATION;
        int sc = SEQUENCE[currentPhase];
        SensorData v = genererValeurs(sc, progress);
        envoyerDonnees(v, sc);
    }
}
