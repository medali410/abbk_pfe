/**
 * DALI PFE — ESP32 : machine DZLI (client Expresse)
 *
 * ID Mongo / MQTT : MAC-1775750118162
 * Broker : broker.hivemq.com (identique au serveur Node)
 *
 * Scénario en boucle :
 *   NORMAL      90 s
 *   DÉGRADATION 60 s
 *   PANNE       120 s (2 minutes)
 *
 * Température en °C (affichage + payload). Le backend convertit pour l’IA.
 * Renseigner WIFI_SSID / WIFI_PASSWORD avant flash.
 *
 * Prérequis : npm run seed:expresse && node ensure_machine_dzli_expresse.js
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// ==================== WiFi ====================
const char *WIFI_SSID = "YOUR_SSID";
const char *WIFI_PASSWORD = "YOUR_PASSWORD";

// IP statique (commenter le bloc WiFi.config dans setup_wifi pour DHCP)
IPAddress local_IP(192, 168, 137, 100);
IPAddress gateway(192, 168, 137, 1);
IPAddress subnet(255, 255, 255, 0);
IPAddress primaryDNS(8, 8, 8, 8);

// ==================== MQTT ====================
const char *MQTT_SERVER = "broker.hivemq.com";
const int MQTT_PORT = 1883;

/** Machine dzli — client expresse (même ID que dans l’app / Mongo) */
const char *MACHINE_ID = "MAC-1775750118162";
const char *MACHINE_NAME = "dzli";
/** ASCII court = moins d’octets sur la ligne MQTT (buffer limité). */
const char *ZONE = "Expresse convoyeur";

const char *TOPIC_LEGACY = "test/machines";

const long SEND_INTERVAL_MS = 3000;

const unsigned long PHASE_NORMAL_MS = 90000;
const unsigned long PHASE_DEGRADE_MS = 60000;
const unsigned long PHASE_PANNE_MS = 120000;

WiFiClient espClient;
PubSubClient client(espClient);
unsigned long lastSend = 0;
unsigned long cycleStart = 0;

enum Phase : uint8_t { PH_NORMAL = 0, PH_DEGRADE = 1, PH_PANNE = 2 };

Phase currentPhase() {
  unsigned long t = millis() - cycleStart;
  if (t < PHASE_NORMAL_MS) return PH_NORMAL;
  if (t < PHASE_NORMAL_MS + PHASE_DEGRADE_MS) return PH_DEGRADE;
  if (t < PHASE_NORMAL_MS + PHASE_DEGRADE_MS + PHASE_PANNE_MS) return PH_PANNE;
  cycleStart = millis();
  return PH_NORMAL;
}

float frand(float lo, float hi) {
  return lo + (float)random(0, 10000) / 10000.0f * (hi - lo);
}

/** Interpolation linéaire (nom évite conflit avec std::lerp du C++20 sur ESP32 3.x). */
static inline float mixf(float a, float b, float t) {
  return a + (b - a) * t;
}

void sampleDzli(Phase ph, float p, float &tempC, float &vibMm, float &torque, int &rpm,
                float &toolWear, float &tempSpreadK) {
  p = constrain(p, 0.0f, 1.0f);
  switch (ph) {
    case PH_NORMAL:
      tempC = frand(28, 42);
      vibMm = frand(4.5f, 8.5f);
      torque = frand(40, 46);
      rpm = random(1450, 1530);
      toolWear = frand(10, 38);
      tempSpreadK = 6;
      break;
    case PH_DEGRADE:
      tempC = mixf(40, 58, p) + frand(-1.2f, 1.2f);
      vibMm = mixf(8.0f, 10.5f, p) + frand(-0.35f, 0.35f);
      torque = mixf(45, 51, p) + frand(-0.5f, 0.5f);
      rpm = (int)mixf(1520.0f, 1620.0f, p) + random(-20, 20);
      toolWear = mixf(40, 95, p) + frand(-5, 6);
      tempSpreadK = 6 + p * 6;
      break;
    case PH_PANNE:
    default:
      tempC = mixf(56, 88, p) + frand(-2.0f, 2.5f);
      vibMm = mixf(10.0f, 12.5f, p) + frand(-0.4f, 1.0f);
      torque = mixf(52, 62, p) + frand(-0.8f, 0.8f);
      rpm = (int)mixf(1600.0f, 1720.0f, p) + random(-25, 25);
      toolWear = mixf(120, 220, p) + frand(-8, 10);
      tempSpreadK = 12 + p * 10;
      break;
  }
}

void publishTelemetry(Phase ph, float p) {
  float tempC, vibMm, torque, toolWear, tempSpreadK;
  int rpm;
  sampleDzli(ph, p, tempC, vibMm, torque, rpm, toolWear, tempSpreadK);

  StaticJsonDocument<512> doc;
  doc["machineId"] = MACHINE_ID;
  doc["name"] = MACHINE_NAME;
  doc["zone"] = ZONE;
  doc["temperature"] = round(tempC * 10) / 10.0;
  doc["rpm"] = rpm;
  doc["torque"] = round(torque * 100) / 100.0;
  doc["tool_wear"] = round(toolWear * 10) / 10.0;
  doc["temp_spread_k"] = round(tempSpreadK * 10) / 10.0;
  doc["wifiRssi"] = WiFi.RSSI();

  JsonObject metrics = doc.createNestedObject("metrics");
  metrics["thermal"] = doc["temperature"];
  metrics["vibration"] = round(vibMm * 10) / 10.0;

  char payload[512];
  size_t n = serializeJson(doc, payload, sizeof(payload) - 1);
  payload[n] = '\0';

  char topicMach[72];
  snprintf(topicMach, sizeof(topicMach), "machines/%s/telemetry", MACHINE_ID);

  bool ok1 = client.publish(topicMach, (const uint8_t *)payload, (unsigned int)n);
  bool ok2 = client.publish(TOPIC_LEGACY, (const uint8_t *)payload, (unsigned int)n);

  Serial.printf("[dzli] phase=%u p=%.2f T=%.1fC rpm=%d Tq=%.1f tw=%.0f | mach:%s leg:%s\n",
                (unsigned)ph, p, tempC, rpm, torque, toolWear,
                ok1 ? "OK" : "FAIL", ok2 ? "OK" : "FAIL");
}

void setup_wifi() {
  Serial.println("WiFi...");
  WiFi.mode(WIFI_STA);
  if (!WiFi.config(local_IP, gateway, subnet, primaryDNS)) {
    Serial.println("(WiFi.config optionnel)");
  }
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int n = 0;
  while (WiFi.status() != WL_CONNECTED && n < 60) {
    delay(500);
    Serial.print(".");
    n++;
  }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("WiFi: echec — verifier SSID/mot de passe");
  }
}

void reconnect_mqtt() {
  for (int a = 0; a < 8 && !client.connected(); a++) {
    String cid = String("ESP32_dzli_") + String(random(0xffff), HEX);
    if (client.connect(cid.c_str())) {
      Serial.println("MQTT connecte");
      client.setBufferSize(2048);
      return;
    }
    delay(1500);
  }
}

void setup() {
  Serial.begin(115200);
  randomSeed((unsigned long)(esp_random() ^ millis()));
  cycleStart = millis();

  Serial.println("\n=== DALI — dzli (Expresse) MAC-1775750118162 ===");
  Serial.println("MQTT: machines/MAC-1775750118162/telemetry + test/machines\n");

  setup_wifi();
  client.setServer(MQTT_SERVER, MQTT_PORT);
  /* Défaut PubSubClient = 256 o → publish() échoue (mach:FAIL) si JSON plus long. */
  client.setBufferSize(2048);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    setup_wifi();
    delay(2000);
    return;
  }
  if (!client.connected()) {
    reconnect_mqtt();
  }
  client.loop();

  unsigned long now = millis();
  if (now - lastSend < SEND_INTERVAL_MS) {
    return;
  }
  lastSend = now;

  Phase ph = currentPhase();
  unsigned long t = now - cycleStart;
  float p = 0;
  if (ph == PH_NORMAL) {
    p = (float)t / (float)PHASE_NORMAL_MS;
  } else if (ph == PH_DEGRADE) {
    p = (float)(t - PHASE_NORMAL_MS) / (float)PHASE_DEGRADE_MS;
  } else {
    p = (float)(t - PHASE_NORMAL_MS - PHASE_DEGRADE_MS) / (float)PHASE_PANNE_MS;
  }

  static Phase last = PH_PANNE;
  if (ph != last) {
    last = ph;
    const char *lab = ph == PH_NORMAL ? "NORMAL" : (ph == PH_DEGRADE ? "DEGRADATION" : "PANNE (2min)");
    Serial.printf("\n>>> %s <<<\n", lab);
  }

  publishTelemetry(ph, p);
}
