/**
 * DALI PFE — ESP32 : 2 machines, MQTT, scénario NORMAL → DÉGRADATION → PANNE (2 min)
 *
 * Température affichée et envoyée en °C (le backend Node convertit pour le modèle IA).
 * Ne pas envoyer "pressure" en bar pour l'IA : omis ici → le serveur déduit pression = couple/rpm.
 * Vibration mm/s dans metrics (affichage) ; le serveur re-map vers l'échelle d'entraînement si > 2.5.
 *
 * Topics : machines/<ID>/telemetry (recommandé) + test/machines (compat).
 *
 * Renseigner WIFI_SSID / WIFI_PASSWORD avant flash.
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// ==================== WiFi (à personnaliser) ====================
const char *WIFI_SSID = "YOUR_SSID";
const char *WIFI_PASSWORD = "YOUR_PASSWORD";

// IP statique optionnelle (commenter WiFi.config si DHCP)
IPAddress local_IP(192, 168, 137, 100);
IPAddress gateway(192, 168, 137, 1);
IPAddress subnet(255, 255, 255, 0);
IPAddress primaryDNS(8, 8, 8, 8);

// ==================== MQTT ====================
const char *MQTT_SERVER = "broker.hivemq.com";
const int MQTT_PORT = 1883;
const char *CLIENT_ID = "ESP32_DALI_IA_SCENARIO";

const long SEND_INTERVAL_MS = 3000;

/** Durées du cycle (ms) — panne = 2 minutes comme demandé */
const unsigned long PHASE_NORMAL_MS = 90000;   // 1 min 30 normal
const unsigned long PHASE_DEGRADE_MS = 60000; // 1 min montée
const unsigned long PHASE_PANNE_MS = 120000;  // 2 min panne

const char *TOPIC_LEGACY = "test/machines";

// ==================== Machine ====================
struct Machine {
  const char *id;
  const char *name;
  const char *zone;
  float tempNormalMin, tempNormalMax;
  float tempDegradeMin, tempDegradeMax;
  float tempPanneMin, tempPanneMax;
  float vibDisplayMin, vibDisplayMax;
  float torqueNormalMin, torqueNormalMax;
  float torquePanneMin, torquePanneMax;
  int rpmNormalMin, rpmNormalMax;
  int rpmPanneMin, rpmPanneMax;
  float toolNormalMax;
  float toolPanneMin;
};

Machine machineHatha = {
  "MAC_HATHA",
  "hatha",
  "Zone A-01",
  46, 58,
  60, 82,
  86, 112,
  0.8f, 3.8f,
  41, 47,
  54, 62,
  1480, 1560,
  1620, 1780,
  45,
  160,
};

Machine machineExpresse = {
  "MAC_EXP",
  "expresse",
  "Zone B-02",
  28, 40,
  44, 58,
  62, 86,
  4.5f, 10.5f,
  40, 46,
  52, 60,
  1450, 1520,
  1580, 1700,
  40,
  150,
};

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

/** Évite le conflit avec std::lerp (C++20) sur toolchains ESP32 récents. */
static inline float mixf(float a, float b, float t) {
  return a + (b - a) * t;
}

void sampleForMachine(Machine &m, Phase ph, float p, float &tempC, float &vibMm, float &torque,
                      int &rpm, float &toolWear, float &tempSpreadK) {
  p = constrain(p, 0.0f, 1.0f);
  switch (ph) {
    case PH_NORMAL:
      tempC = frand(m.tempNormalMin, m.tempNormalMax);
      vibMm = frand(m.vibDisplayMin, m.vibDisplayMax);
      torque = frand(m.torqueNormalMin, m.torqueNormalMax);
      rpm = random(m.rpmNormalMin, m.rpmNormalMax);
      toolWear = frand(8, m.toolNormalMax);
      tempSpreadK = 6;
      break;
    case PH_DEGRADE:
      tempC = mixf(m.tempNormalMax - 2, m.tempDegradeMax, p) + frand(-1.5f, 1.5f);
      vibMm = mixf(m.vibDisplayMax * 0.6f, m.vibDisplayMax * 1.15f, p) + frand(-0.4f, 0.4f);
      torque = mixf(m.torqueNormalMax - 1, m.torquePanneMin - 2, p) + frand(-0.6f, 0.6f);
      rpm = (int)mixf((float)m.rpmNormalMax, (float)m.rpmPanneMin, p) + random(-18, 18);
      toolWear = mixf(m.toolNormalMax, m.toolPanneMin * 0.55f, p) + frand(-6, 8);
      tempSpreadK = 6 + p * 6;
      break;
    case PH_PANNE:
    default:
      tempC = mixf(m.tempDegradeMax - 4, m.tempPanneMax, p) + frand(-2.0f, 2.5f);
      vibMm = mixf(m.vibDisplayMax * 1.0f, m.vibDisplayMax * 1.35f, p) + frand(-0.5f, 1.2f);
      torque = mixf(m.torquePanneMin - 4, m.torquePanneMax, p) + frand(-0.8f, 0.8f);
      rpm = (int)mixf((float)m.rpmPanneMin, (float)m.rpmPanneMax, p) + random(-25, 25);
      toolWear = mixf(m.toolPanneMin * 0.7f, m.toolPanneMin + 70, p) + frand(-10, 12);
      tempSpreadK = 12 + p * 10;
      break;
  }
}

void publishMachine(Machine &m, Phase ph, float p) {
  float tempC, vibMm, torque, toolWear, tempSpreadK;
  int rpm;
  sampleForMachine(m, ph, p, tempC, vibMm, torque, rpm, toolWear, tempSpreadK);

  StaticJsonDocument<512> doc;
  doc["machineId"] = m.id;
  doc["name"] = m.name;
  doc["zone"] = m.zone;
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

  char topicMach[80];
  snprintf(topicMach, sizeof(topicMach), "machines/%s/telemetry", m.id);

  bool ok1 = client.publish(topicMach, (const uint8_t *)payload, (unsigned int)n);
  bool ok2 = client.publish(TOPIC_LEGACY, (const uint8_t *)payload, (unsigned int)n);

  Serial.printf("[%s] %s phase=%u p=%.2f T=%.1f°C rpm=%d Tq=%.1f tw=%.0f -> %s %s\n",
                m.id, m.name, (unsigned)ph, p, tempC, rpm, torque, toolWear,
                ok1 ? "machOK" : "machFAIL", ok2 ? "legacyOK" : "legacyFAIL");
}

void setup_wifi() {
  Serial.println("WiFi...");
  WiFi.mode(WIFI_STA);
  if (!WiFi.config(local_IP, gateway, subnet, primaryDNS)) {
    Serial.println("(config IP statique ignorée ou erreur)");
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
    Serial.println("WiFi: echec");
  }
}

void reconnect_mqtt() {
  int a = 0;
  while (!client.connected() && a < 8) {
    a++;
    String cid = String(CLIENT_ID) + String(random(0xffff), HEX);
    if (client.connect(cid.c_str())) {
      Serial.println("MQTT OK");
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

  Serial.println("\n=== DALI ESP32 scenario IA ===");
  Serial.println("Phases: NORMAL 90s | DEGRADE 60s | PANNE 120s (cycle)\n");

  setup_wifi();
  client.setServer(MQTT_SERVER, MQTT_PORT);
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

  static Phase lastPh = PH_PANNE;
  if (ph != lastPh) {
    lastPh = ph;
    const char *lab = ph == PH_NORMAL ? "NORMAL" : (ph == PH_DEGRADE ? "DEGRADATION" : "PANNE (2min)");
    Serial.printf("\n>>> Phase: %s <<<\n\n", lab);
  }

  publishMachine(machineHatha, ph, p);
  delay(120);
  publishMachine(machineExpresse, ph, p);
}
