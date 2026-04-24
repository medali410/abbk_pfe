/*
 * ================================================================
 *  DALI PFE - Simulateur de Scénarios de Panne (ESP32 + MQTT)
 * ================================================================
 *
 *  Cycle automatique :
 *    - 5 min données NORMALES
 *    - 5 min scénario SURCHAUFFE
 *    - 5 min données NORMALES
 *    - 5 min scénario VIBRATION (ROULEMENT)
 *    - 5 min données NORMALES
 *    - 5 min scénario SURCHARGE
 *    - 5 min données NORMALES
 *    - 5 min scénario ELECTRIQUE
 *    - 5 min données NORMALES
 *    - 5 min scénario USURE_GENERALE
 *    - 5 min données NORMALES
 *    - 5 min scénario PRESSION (combiné)
 *    - ... recommence
 *
 *  CONFIGURATION :
 *    Modifier MACHINE_ID ci-dessous avec l'ID de votre machine
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// ===================== CONFIGURATION =====================

// >>> METTRE L'ID DE VOTRE MACHINE ICI <<<
#define MACHINE_ID    ""
// Exemples: "MAC-00A1", "MAC-B2C3", etc.

#define MOTOR_TYPE    "EL_M"

// WiFi
#define WIFI_SSID     "YOUR_WIFI"
#define WIFI_PASS     "YOUR_PASSWORD"

// MQTT
#define MQTT_BROKER   "broker.hivemq.com"
#define MQTT_PORT     1883

// Timing
#define SCENARIO_DURATION_MS  300000   // 5 minutes par scénario
#define SEND_INTERVAL_MS      3000     // Envoi toutes les 3 secondes

// ===================== SCÉNARIOS =====================

enum Scenario {
    NORMAL,
    SURCHAUFFE,
    ROULEMENT_VIBRATION,
    SURCHARGE,
    ELECTRIQUE,
    USURE_GENERALE,
    PRESSION_ANOMALIE,
    NUM_SCENARIOS
};

const char* scenarioNames[] = {
    "NORMAL",
    "SURCHAUFFE",
    "ROULEMENT",
    "SURCHARGE",
    "ELECTRIQUE",
    "USURE_GENERALE",
    "PRESSION"
};

// Séquence: NORMAL -> panne -> NORMAL -> panne -> ...
// Total: 12 phases (6 normales + 6 pannes)
Scenario scenarioSequence[] = {
    NORMAL, SURCHAUFFE,
    NORMAL, ROULEMENT_VIBRATION,
    NORMAL, SURCHARGE,
    NORMAL, ELECTRIQUE,
    NORMAL, USURE_GENERALE,
    NORMAL, PRESSION_ANOMALIE,
};
const int SEQUENCE_LENGTH = 12;

// ===================== VARIABLES =====================

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);

unsigned long lastSend = 0;
unsigned long scenarioStart = 0;
int currentPhase = 0;
float progressInScenario = 0.0;

// ===================== GÉNÉRATION DONNÉES =====================

float randomFloat(float minVal, float maxVal) {
    return minVal + (float)random(0, 10000) / 10000.0 * (maxVal - minVal);
}

struct SensorData {
    float temperature;
    float pression;
    float puissance;
    float vibration;
    float presence;
    float magnetique;
    float infrarouge;
};

SensorData generateNormal() {
    SensorData d;
    d.temperature = randomFloat(35.0, 55.0);
    d.pression    = randomFloat(0.02, 0.04);
    d.puissance   = randomFloat(50000, 70000);
    d.vibration   = randomFloat(0.5, 1.5);
    d.presence    = 1.0;
    d.magnetique  = randomFloat(0.4, 0.7);
    d.infrarouge  = d.temperature + randomFloat(-3.0, 5.0);
    return d;
}

SensorData generateSurchauffe(float progress) {
    // Température monte progressivement de 60 à 120°C
    SensorData d;
    d.temperature = 60.0 + progress * 60.0 + randomFloat(-3.0, 3.0);
    d.pression    = randomFloat(0.03, 0.06);
    d.puissance   = randomFloat(80000, 130000);
    d.vibration   = 1.5 + progress * 2.0 + randomFloat(-0.3, 0.3);
    d.presence    = 1.0;
    d.magnetique  = randomFloat(0.5, 0.8);
    d.infrarouge  = d.temperature + randomFloat(5.0, 20.0);

    // Oscillations thermiques typiques avant surchauffe
    if (progress > 0.3) {
        d.temperature += sin(progress * 20.0) * 8.0;
    }
    return d;
}

SensorData generateRoulement(float progress) {
    // Vibrations très élevées, croissantes
    SensorData d;
    d.temperature = 50.0 + progress * 25.0 + randomFloat(-2.0, 2.0);
    d.pression    = randomFloat(0.02, 0.04);
    d.puissance   = randomFloat(55000, 85000);
    d.vibration   = 3.0 + progress * 5.0 + randomFloat(-0.5, 0.5);
    d.presence    = 1.0;
    d.magnetique  = randomFloat(0.3, 0.7);
    d.infrarouge  = d.temperature + randomFloat(0.0, 8.0);

    // Pics périodiques de vibration
    if (random(0, 100) < 30) {
        d.vibration += randomFloat(2.0, 4.0);
    }
    return d;
}

SensorData generateSurcharge(float progress) {
    // Puissance très élevée, pression monte
    SensorData d;
    d.temperature = 55.0 + progress * 30.0 + randomFloat(-2.0, 2.0);
    d.pression    = 0.05 + progress * 0.08 + randomFloat(-0.01, 0.01);
    d.puissance   = 120000 + progress * 80000 + randomFloat(-5000, 5000);
    d.vibration   = 2.0 + progress * 2.5 + randomFloat(-0.3, 0.3);
    d.presence    = 1.0;
    d.magnetique  = randomFloat(0.6, 0.95);
    d.infrarouge  = d.temperature + randomFloat(3.0, 10.0);
    return d;
}

SensorData generateElectrique(float progress) {
    // Puissance fluctuante, magnétique erratique
    SensorData d;
    d.temperature = 45.0 + progress * 40.0 + randomFloat(-5.0, 5.0);
    d.pression    = randomFloat(0.01, 0.03);

    // Fluctuations brutales de puissance
    if (random(0, 100) < 40) {
        d.puissance = randomFloat(10000, 30000);  // chute
    } else {
        d.puissance = randomFloat(100000, 170000); // pic
    }

    d.vibration   = randomFloat(1.0, 3.0);
    d.presence    = random(0, 100) < 20 ? 0.0 : 1.0; // coupures présence
    d.magnetique  = random(0, 100) < 50 ? randomFloat(0.05, 0.15) : randomFloat(0.85, 0.98);
    d.infrarouge  = d.temperature + randomFloat(-10.0, 20.0);
    return d;
}

SensorData generateUsure(float progress) {
    // Dégradation lente sur tous les capteurs
    SensorData d;
    d.temperature = 50.0 + progress * 20.0 + randomFloat(-3.0, 3.0);
    d.pression    = 0.03 + progress * 0.04 + randomFloat(-0.005, 0.005);
    d.puissance   = 60000 - progress * 20000 + randomFloat(-3000, 3000);
    d.vibration   = 2.0 + progress * 3.5 + randomFloat(-0.5, 0.5);
    d.presence    = 1.0;
    d.magnetique  = 0.5 - progress * 0.3 + randomFloat(-0.05, 0.05);
    d.infrarouge  = d.temperature + randomFloat(0.0, 10.0);
    return d;
}

SensorData generatePression(float progress) {
    // Chutes et pics de pression
    SensorData d;
    d.temperature = 55.0 + progress * 15.0 + randomFloat(-2.0, 2.0);

    // Oscillations pression
    d.pression = 0.04 + sin(progress * 15.0) * 0.05 + randomFloat(-0.01, 0.01);
    if (d.pression < 0.005) d.pression = 0.005;

    d.puissance   = randomFloat(60000, 90000);
    d.vibration   = 1.5 + progress * 1.5 + randomFloat(-0.3, 0.3);
    d.presence    = 1.0;
    d.magnetique  = randomFloat(0.4, 0.7);
    d.infrarouge  = d.temperature + randomFloat(0.0, 5.0);
    return d;
}

SensorData generateData(Scenario scenario, float progress) {
    switch (scenario) {
        case SURCHAUFFE:           return generateSurchauffe(progress);
        case ROULEMENT_VIBRATION:  return generateRoulement(progress);
        case SURCHARGE:            return generateSurcharge(progress);
        case ELECTRIQUE:           return generateElectrique(progress);
        case USURE_GENERALE:       return generateUsure(progress);
        case PRESSION_ANOMALIE:    return generatePression(progress);
        default:                   return generateNormal();
    }
}

// ===================== WIFI =====================

void connectWiFi() {
    Serial.print("WiFi");
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30) {
        delay(500);
        Serial.print(".");
        attempts++;
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.print(" OK! IP=");
        Serial.println(WiFi.localIP());
    } else {
        Serial.println(" ECHEC!");
        delay(3000);
        ESP.restart();
    }
}

// ===================== MQTT =====================

void mqttCallback(char* topic, byte* payload, unsigned int length) {
    String msg;
    for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];
    Serial.print("[MQTT] ");
    Serial.print(topic);
    Serial.print(": ");
    Serial.println(msg);
}

void connectMQTT() {
    mqtt.setServer(MQTT_BROKER, MQTT_PORT);
    mqtt.setCallback(mqttCallback);

    String clientId = "sim_" + String(MACHINE_ID) + "_" + String(random(0, 9999));
    if (mqtt.connect(clientId.c_str())) {
        Serial.println("MQTT OK!");
        String cmdTopic = "machines/" + String(MACHINE_ID) + "/control";
        mqtt.subscribe(cmdTopic.c_str());
    } else {
        Serial.print("MQTT ECHEC rc=");
        Serial.println(mqtt.state());
    }
}

// ===================== ENVOI =====================

void sendData(SensorData data, Scenario scenario) {
    JsonDocument doc;
    doc["machineId"]    = MACHINE_ID;
    doc["type_moteur"]  = MOTOR_TYPE;
    doc["temperature"]  = round(data.temperature * 10.0) / 10.0;
    doc["pressure"]     = round(data.pression * 1000.0) / 1000.0;
    doc["power"]        = round(data.puissance);
    doc["vibration"]    = round(data.vibration * 100.0) / 100.0;
    doc["presence"]     = (int)data.presence;
    doc["magnetic"]     = round(data.magnetique * 100.0) / 100.0;
    doc["infrared"]     = round(data.infrarouge * 10.0) / 10.0;
    doc["ultrasonic"]   = randomFloat(20.0, 60.0);
    doc["rpm"]          = 1500;
    doc["torque"]       = 40.0;
    doc["scenario_sim"] = scenarioNames[scenario];

    String body;
    serializeJson(doc, body);

    // Publier sur le topic MQTT de la machine
    String topic = "machines/" + String(MACHINE_ID) + "/telemetry";
    mqtt.publish(topic.c_str(), body.c_str());

    // Aussi publier sur le topic général
    mqtt.publish("test/machines", body.c_str());

    Serial.printf("[%s] %s | T=%.1f V=%.1f P=%.0f Mag=%.2f\n",
                  MACHINE_ID,
                  scenarioNames[scenario],
                  data.temperature,
                  data.vibration,
                  data.puissance,
                  data.magnetique);
}

// ===================== SETUP & LOOP =====================

void setup() {
    Serial.begin(115200);
    randomSeed(analogRead(0));

    Serial.println("\n==========================================");
    Serial.println("  DALI PFE - SIMULATEUR DE PANNES");
    Serial.print("  Machine: ");
    Serial.println(MACHINE_ID);
    Serial.println("==========================================");
    Serial.println("  Cycle: 5min Normal -> 5min Panne");
    Serial.println("  6 types: Surchauffe, Roulement,");
    Serial.println("  Surcharge, Electrique, Usure, Pression");
    Serial.println("==========================================\n");

    if (strlen(MACHINE_ID) == 0) {
        Serial.println("!!! ERREUR: MACHINE_ID est vide !!!");
        Serial.println("Modifiez MACHINE_ID dans le code.");
        while (true) delay(1000);
    }

    connectWiFi();
    connectMQTT();

    scenarioStart = millis();
    currentPhase = 0;
}

void loop() {
    if (WiFi.status() != WL_CONNECTED) connectWiFi();
    if (!mqtt.connected()) connectMQTT();
    mqtt.loop();

    unsigned long now = millis();

    // Changer de phase toutes les 5 minutes
    if (now - scenarioStart >= SCENARIO_DURATION_MS) {
        scenarioStart = now;
        currentPhase = (currentPhase + 1) % SEQUENCE_LENGTH;
        Serial.println("\n========================================");
        Serial.printf("  PHASE %d/%d : %s\n",
                      currentPhase + 1,
                      SEQUENCE_LENGTH,
                      scenarioNames[scenarioSequence[currentPhase]]);
        Serial.println("========================================\n");
    }

    // Progression dans le scénario actuel (0.0 -> 1.0)
    progressInScenario = (float)(now - scenarioStart) / (float)SCENARIO_DURATION_MS;

    // Envoyer données à intervalles réguliers
    if (now - lastSend >= SEND_INTERVAL_MS) {
        lastSend = now;
        Scenario current = scenarioSequence[currentPhase];
        SensorData data = generateData(current, progressInScenario);
        sendData(data, current);
    }
}
