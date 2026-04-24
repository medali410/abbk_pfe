/**
 * DALI PFE — télémétrie MQTT avec rampe 0→1 (6 scénarios panne, comme simulate_scenarios.js).
 * 0=SURCHAUFFE 1=ROULEMENT 2=SURCHARGE 3=ELECTRIQUE 4=USURE_GENERALE 5=PRESSION
 *
 * CYCLE_ALL_SCENARIOS = true  → enchaîne automatiquement 0…5 à chaque fin de rampe (les 6 scénarios).
 * CYCLE_ALL_SCENARIOS = false → un seul scénario fixe : SCENARIO_MODE (0..5).
 *
 * Prérequis :
 *  1. Créer une machine dans MongoDB / dashboard et copier son _id exact (ex. 674a... ou MAC-xxx).
 *  2. Remplir WIFI_SSID, WIFI_PASS, MACHINE_ID ci-dessous.
 *  3. Backend Node branché sur le même broker que MQTT_BROKER (défaut server.js : mqtt://broker.hivemq.com).
 *  4. Service Python USE_TABULAR=1 sur le port attendu par ML_SERVER (souvent 5000).
 *
 * Librairies (Gestionnaire de cartes Arduino) :
 *  - PubSubClient par Nick O'Leary
 *  - ArduinoJson v6 (éviter v7 : syntaxe doc.to<Json>() différente)
 *
 * Topic : machines/<MACHINE_ID>/telemetry
 * Corps : JSON avec air/process en Kelvin + rpm, torque, tool_wear (aligné buildMlPayload / modèle tabulaire).
 *
 * Pourcentage de panne (prob_panne) :
 *  - MQTT seul : le calcul est sur le serveur → l’ESP ne le reçoit pas sur le bus.
 *  - Remplissez NODE_PREDICT_URL (IP du PC avec Node, même WiFi que l’ESP) pour afficher
 *    prob_panne / niveau / ml_prob sur le Moniteur série après chaque envoi.
 */

/*
 * OBLIGATOIRE avant PubSubClient : taille max du paquet MQTT (topic + JSON).
 * Trop petit → mqtt.publish() renvoie false → moniteur affiche "FAIL" → rien sur l’app web.
 */
#define MQTT_MAX_PACKET_SIZE 4096
#include <WiFi.h>
#include <HTTPClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <math.h>

// ---------- À CONFIGURER ----------
static const char *WIFI_SSID = "TT_CD81";
/** Ne commitez jamais le vrai mot de passe dans Git : remplissez localement avant flash. */
static const char *WIFI_PASS = "VOTRE_MOT_DE_PASSE_WIFI";

/** ID MongoDB de la machine (chaîne exacte vue dans le dashboard / API). */
/** Ex. machine « dzli » (npm run seed:dzli) : */
static const char *MACHINE_ID = "MAC-1775750118162";

static const char *MQTT_SERVER = "broker.hivemq.com";
static const uint16_t MQTT_PORT = 1883;

/** Nombre de pas de la rampe (une publication toutes les PUBLISH_INTERVAL_MS). */
static const int RAMP_STEPS = 40;

/** Pause entre deux envois (ms). */
static const unsigned long PUBLISH_INTERVAL_MS = 2500;

/** Type moteur pour le ML : "EL_S", "EL_M", "EL_L" (doit matcher ton profil machine). */
static const char *TYPE_MOTEUR = "EL_M";

/** Si false : scénario fixe SCENARIO_MODE (0..5). Ignoré quand CYCLE_ALL_SCENARIOS est true. */
static const bool CYCLE_ALL_SCENARIOS = true;

/** 0..5 : utilisé seulement quand CYCLE_ALL_SCENARIOS = false. */
static const uint8_t SCENARIO_MODE = 0;

/**
 * URL complète du POST /api/predict sur ton backend Node (même JSON que la télémétrie).
 * Exemple : "http://192.168.1.20:3001/api/predict"
 * Laisser "" pour ne pas appeler l’API (pas d’affichage du % sur le Serial).
 */
static const char *NODE_PREDICT_URL = "";

// ----------------------------------

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);

/** Affiche prob_panne (fusionné côté Node sur cette route), ml_prob, niveau. */
void printPredictionFromBackend(const char *jsonBody) {
  if (!NODE_PREDICT_URL || !NODE_PREDICT_URL[0]) {
    return;
  }
  HTTPClient http;
  http.setTimeout(8000);
  if (!http.begin(NODE_PREDICT_URL)) {
    Serial.println("HTTP begin KO");
    return;
  }
  http.addHeader("Content-Type", "application/json");
  int code = http.POST((uint8_t *)jsonBody, strlen(jsonBody));
  if (code != 200) {
    Serial.print("predict HTTP ");
    Serial.println(code);
    http.end();
    return;
  }
  String resp = http.getString();
  http.end();

  StaticJsonDocument<768> rd;
  DeserializationError err = deserializeJson(rd, resp);
  if (err) {
    Serial.println("JSON reponse IA illisible");
    return;
  }

  float prob = rd["prob_panne"] | -1.f;

  Serial.print("   >> prob_panne=");
  Serial.print(prob, 1);
  Serial.print("%  niveau=");
  if (rd["niveau"].isNull()) {
    Serial.print("?");
  } else {
    Serial.print(rd["niveau"].as<const char *>());
  }
  /* Sur MQTT le backend envoie aussi ml_prob ; sur POST /api/predict souvent absent */
  if (rd.containsKey("ml_prob")) {
    Serial.print("  ml_prob=");
    Serial.print(rd["ml_prob"].as<float>(), 1);
    Serial.print("%");
  }
  Serial.println();
}

char topicBuf[96];

void buildTopic() {
  snprintf(topicBuf, sizeof(topicBuf), "machines/%s/telemetry", MACHINE_ID);
}

/** Uniforme dans [a, b] (b > a). */
static float frandRange(float a, float b) {
  if (b <= a) return a;
  uint32_t u = esp_random();
  float u01 = (u & 0xffffff) / 16777216.f;
  return a + u01 * (b - a);
}

/**
 * t dans [0,1] : scénario **surchauffe** (défaut panne température côté seuils EL_M ~65 °C warn / 85 °C crit).
 * - Air : montée modérée (ambiance / refroidissement insuffisant).
 * - Process : montée forte + smoothstep fin → pic thermique sans faire exploser RPM/usure (signal « thermique »).
 * Unités : Kelvin pour air/process (comme buildMlPayload / AI4I).
 */
void fillPayloadThermalRamp(JsonObject root, float t) {
  if (t < 0.f) t = 0.f;
  if (t > 1.f) t = 1.f;

  /* smoothstep(t) : accélère la montée en température en fin de cycle */
  const float s = t * t * (3.0f - 2.0f * t);

  const float airK = 297.5f + s * 14.0f;    // ~24 °C → ~38 °C (moyenne côté air)
  const float procK = 306.5f + s * 62.0f;   // ~33 °C → ~96 °C process (moyenne °C > seuil warn ~65)

  /* Moteur « nominal » puis légère montée charge (secondaire par rapport à la température) */
  const float rpm = 1480.f + s * 220.f;
  const float torque = 42.f + s * 10.f;
  const float toolWear = 18.f + s * 55.f;

  root["machineId"] = MACHINE_ID;
  root["type_moteur"] = TYPE_MOTEUR;
  root["air_temperature"] = airK;
  root["process_temperature"] = procK;
  root["rpm"] = rpm;
  root["torque"] = torque;
  root["tool_wear"] = toolWear;

  /* °C affichés = moyenne (T_air + T_process) / 2 — suit la surcharge thermique */
  const float tempC = (airK + procK) * 0.5f - 273.15f;
  root["temperature"] = tempC;
  /* Vibration : légère hausse (dilatation / déséquilibre thermique), sans voler le scénario */
  root["vibration"] = 0.9f + s * 2.4f;
  root["presence"] = 1;
  root["magnetic"] = 48.f + s * 25.f;

  JsonObject metrics = root.createNestedObject("metrics");
  metrics["thermal"] = tempC;
  metrics["pressure"] = torque / (rpm > 1.f ? rpm : 1.f);
  metrics["power"] = torque * rpm;
  metrics["ultrasonic"] = 35.f + s * 40.f;
  metrics["presence"] = 1;
  metrics["magnetic"] = 48.f + s * 25.f;
  metrics["infrared"] = procK - 273.15f;
  metrics["rpm"] = rpm;
  metrics["torque"] = torque;
  metrics["tool_wear"] = toolWear;
}

/**
 * ROULEMENT — même esprit que generateRoulement() dans simulate_scenarios.js :
 * vibration élevée (3 → ~8+), température 50–75 °C, puissance 55–85 kW, pression basse, ultrasons variables.
 */
void fillPayloadRoulement(JsonObject root, float t) {
  if (t < 0.f) t = 0.f;
  if (t > 1.f) t = 1.f;
  const float s = t * t * (3.0f - 2.0f * t);

  float tempC = 50.f + s * 25.f + frandRange(-2.f, 2.f);
  float vib = 3.f + s * 5.f + frandRange(-0.5f, 0.5f);
  if ((esp_random() % 10) < 3) {
    vib += frandRange(2.f, 4.f);
  }
  if (vib > 12.f) vib = 12.f;

  const float airK = tempC - 2.5f + 273.15f;
  const float procK = tempC + 3.5f + 273.15f;
  const float rpm = 1500.f + frandRange(-25.f, 25.f);
  const float torque = 41.f + s * 5.f + frandRange(-1.2f, 1.2f);
  const float toolWear = 10.f + s * 55.f + frandRange(0.f, 6.f);

  const float press = frandRange(0.02f, 0.04f);
  const float power = 55000.f + s * 30000.f + frandRange(-4500.f, 4500.f);
  const float magnetic = frandRange(30.f, 70.f);
  const float ultrasonic = frandRange(15.f, 70.f);
  const float infrared = tempC + frandRange(0.f, 8.f);

  root["machineId"] = MACHINE_ID;
  root["type_moteur"] = TYPE_MOTEUR;
  root["air_temperature"] = airK;
  root["process_temperature"] = procK;
  root["rpm"] = rpm;
  root["torque"] = torque;
  root["tool_wear"] = toolWear;

  root["temperature"] = tempC;
  root["pressure"] = press;
  root["power"] = power;
  root["vibration"] = vib;
  root["presence"] = 1;
  root["magnetic"] = magnetic;
  root["infrared"] = infrared;
  root["ultrasonic"] = ultrasonic;

  JsonObject metrics = root.createNestedObject("metrics");
  metrics["thermal"] = tempC;
  metrics["pressure"] = press;
  metrics["power"] = power;
  metrics["ultrasonic"] = ultrasonic;
  metrics["presence"] = 1;
  metrics["magnetic"] = magnetic;
  metrics["infrared"] = infrared;
  metrics["rpm"] = rpm;
  metrics["torque"] = torque;
  metrics["tool_wear"] = toolWear;
}

/** t ∈ [0,1] → smoothstep, même courbe que les autres scénarios. */
static float rampS(float t) {
  if (t < 0.f) t = 0.f;
  if (t > 1.f) t = 1.f;
  return t * t * (3.0f - 2.0f * t);
}

/**
 * SURCHARGE — generateSurcharge : T 55→~85 °C, pression 0.05→0.13, puissance 120→200 kW, vibration modérée.
 */
void fillPayloadSurcharge(JsonObject root, float t) {
  const float s = rampS(t);
  float tempC = 55.f + s * 30.f + frandRange(-2.f, 2.f);
  float press = 0.05f + s * 0.08f + frandRange(-0.01f, 0.01f);
  float power = 120000.f + s * 80000.f + frandRange(-5000.f, 5000.f);
  float vib = 2.f + s * 2.5f + frandRange(-0.3f, 0.3f);
  float magnetic = frandRange(60.f, 95.f);
  float infrared = tempC + frandRange(3.f, 10.f);
  float ultrasonic = frandRange(20.f, 60.f);

  float rpm = 1520.f + frandRange(-40.f, 40.f);
  if (rpm < 200.f) rpm = 200.f;
  float torque = power / rpm;
  if (torque > 120.f) torque = 120.f;
  if (torque < 25.f) torque = 25.f;
  float toolWear = 20.f + s * 50.f;

  const float airK = tempC - 2.f + 273.15f;
  const float procK = tempC + 5.f + 273.15f;

  root["machineId"] = MACHINE_ID;
  root["type_moteur"] = TYPE_MOTEUR;
  root["air_temperature"] = airK;
  root["process_temperature"] = procK;
  root["rpm"] = rpm;
  root["torque"] = torque;
  root["tool_wear"] = toolWear;
  root["temperature"] = tempC;
  root["pressure"] = press;
  root["power"] = power;
  root["vibration"] = vib;
  root["presence"] = 1;
  root["magnetic"] = magnetic;
  root["infrared"] = infrared;
  root["ultrasonic"] = ultrasonic;

  JsonObject metrics = root.createNestedObject("metrics");
  metrics["thermal"] = tempC;
  metrics["pressure"] = press;
  metrics["power"] = power;
  metrics["ultrasonic"] = ultrasonic;
  metrics["presence"] = 1;
  metrics["magnetic"] = magnetic;
  metrics["infrared"] = infrared;
  metrics["rpm"] = rpm;
  metrics["torque"] = torque;
  metrics["tool_wear"] = toolWear;
}

/**
 * ELECTRIQUE — generateElectrique : T 45→~85 °C, puissance soit très basse soit très haute, magnétique extrême.
 */
void fillPayloadElectrique(JsonObject root, float t) {
  const float s = rampS(t);
  float tempC = 45.f + s * 40.f + frandRange(-5.f, 5.f);
  bool lowPower = (esp_random() % 10) < 4;
  float power = lowPower ? frandRange(10000.f, 30000.f) : frandRange(100000.f, 170000.f);
  float press = frandRange(0.01f, 0.03f);
  float vib = frandRange(1.f, 3.f);
  int presence = (esp_random() % 10) < 2 ? 0 : 1;
  float magnetic = (esp_random() % 2) == 0 ? frandRange(5.f, 15.f) : frandRange(85.f, 98.f);
  float infrared = tempC + frandRange(-10.f, 20.f);
  float ultrasonic = frandRange(20.f, 60.f);

  float rpm = 1490.f + frandRange(-50.f, 50.f);
  if (rpm < 200.f) rpm = 200.f;
  float torque = power / rpm;
  if (torque > 130.f) torque = 130.f;
  if (torque < 8.f) torque = 8.f;
  float toolWear = 5.f + s * 25.f;

  const float airK = tempC - 3.f + 273.15f;
  const float procK = tempC + 4.f + 273.15f;

  root["machineId"] = MACHINE_ID;
  root["type_moteur"] = TYPE_MOTEUR;
  root["air_temperature"] = airK;
  root["process_temperature"] = procK;
  root["rpm"] = rpm;
  root["torque"] = torque;
  root["tool_wear"] = toolWear;
  root["temperature"] = tempC;
  root["pressure"] = press;
  root["power"] = power;
  root["vibration"] = vib;
  root["presence"] = presence;
  root["magnetic"] = magnetic;
  root["infrared"] = infrared;
  root["ultrasonic"] = ultrasonic;

  JsonObject metrics = root.createNestedObject("metrics");
  metrics["thermal"] = tempC;
  metrics["pressure"] = press;
  metrics["power"] = power;
  metrics["ultrasonic"] = ultrasonic;
  metrics["presence"] = presence;
  metrics["magnetic"] = magnetic;
  metrics["infrared"] = infrared;
  metrics["rpm"] = rpm;
  metrics["torque"] = torque;
  metrics["tool_wear"] = toolWear;
}

/**
 * USURE_GENERALE — generateUsure : T 50→~70 °C, pression monte, puissance baisse, vibration et usure montent.
 */
void fillPayloadUsure(JsonObject root, float t) {
  const float s = rampS(t);
  float tempC = 50.f + s * 20.f + frandRange(-3.f, 3.f);
  float press = 0.03f + s * 0.04f + frandRange(-0.005f, 0.005f);
  float power = 60000.f - s * 20000.f + frandRange(-3000.f, 3000.f);
  if (power < 15000.f) power = 15000.f;
  float vib = 2.f + s * 3.5f + frandRange(-0.5f, 0.5f);
  float magnetic = (50.f - s * 30.f) + frandRange(-5.f, 5.f);
  if (magnetic < 5.f) magnetic = 5.f;
  float infrared = tempC + frandRange(0.f, 10.f);
  float ultrasonic = frandRange(20.f, 60.f);

  float rpm = 1420.f + frandRange(-30.f, 30.f);
  if (rpm < 200.f) rpm = 200.f;
  float torque = power / rpm;
  if (torque > 90.f) torque = 90.f;
  if (torque < 20.f) torque = 20.f;
  float toolWear = 35.f + s * 80.f + frandRange(0.f, 10.f);

  const float airK = tempC - 2.5f + 273.15f;
  const float procK = tempC + 4.f + 273.15f;

  root["machineId"] = MACHINE_ID;
  root["type_moteur"] = TYPE_MOTEUR;
  root["air_temperature"] = airK;
  root["process_temperature"] = procK;
  root["rpm"] = rpm;
  root["torque"] = torque;
  root["tool_wear"] = toolWear;
  root["temperature"] = tempC;
  root["pressure"] = press;
  root["power"] = power;
  root["vibration"] = vib;
  root["presence"] = 1;
  root["magnetic"] = magnetic;
  root["infrared"] = infrared;
  root["ultrasonic"] = ultrasonic;

  JsonObject metrics = root.createNestedObject("metrics");
  metrics["thermal"] = tempC;
  metrics["pressure"] = press;
  metrics["power"] = power;
  metrics["ultrasonic"] = ultrasonic;
  metrics["presence"] = 1;
  metrics["magnetic"] = magnetic;
  metrics["infrared"] = infrared;
  metrics["rpm"] = rpm;
  metrics["torque"] = torque;
  metrics["tool_wear"] = toolWear;
}

/**
 * PRESSION — generatePression : pression oscillante sin(t*15), T 55→~70 °C, puissance 60–90 kW.
 */
void fillPayloadPression(JsonObject root, float t) {
  if (t < 0.f) t = 0.f;
  if (t > 1.f) t = 1.f;
  const float s = rampS(t);

  float tempC = 55.f + s * 15.f + frandRange(-2.f, 2.f);
  float press = 0.04f + sinf(t * 15.0f) * 0.05f + frandRange(-0.01f, 0.01f);
  if (press < 0.005f) press = 0.005f;
  float power = frandRange(60000.f, 90000.f);
  float vib = 1.5f + s * 1.5f + frandRange(-0.3f, 0.3f);
  float magnetic = frandRange(40.f, 70.f);
  float infrared = tempC + frandRange(0.f, 5.f);
  float ultrasonic = frandRange(20.f, 60.f);

  float rpm = 1500.f + frandRange(-20.f, 20.f);
  float torque = 40.f + frandRange(-3.f, 3.f);
  float toolWear = 22.f + s * 35.f;

  const float airK = tempC - 2.f + 273.15f;
  const float procK = tempC + 3.f + 273.15f;

  root["machineId"] = MACHINE_ID;
  root["type_moteur"] = TYPE_MOTEUR;
  root["air_temperature"] = airK;
  root["process_temperature"] = procK;
  root["rpm"] = rpm;
  root["torque"] = torque;
  root["tool_wear"] = toolWear;
  root["temperature"] = tempC;
  root["pressure"] = press;
  root["power"] = power;
  root["vibration"] = vib;
  root["presence"] = 1;
  root["magnetic"] = magnetic;
  root["infrared"] = infrared;
  root["ultrasonic"] = ultrasonic;

  JsonObject metrics = root.createNestedObject("metrics");
  metrics["thermal"] = tempC;
  metrics["pressure"] = press;
  metrics["power"] = power;
  metrics["ultrasonic"] = ultrasonic;
  metrics["presence"] = 1;
  metrics["magnetic"] = magnetic;
  metrics["infrared"] = infrared;
  metrics["rpm"] = rpm;
  metrics["torque"] = torque;
  metrics["tool_wear"] = toolWear;
}

static const char *scenarioName(uint8_t m) {
  switch (m > 5 ? 0 : m) {
    case 1: return "ROULEMENT";
    case 2: return "SURCHARGE";
    case 3: return "ELECTRIQUE";
    case 4: return "USURE_GENERALE";
    case 5: return "PRESSION";
    default: return "SURCHAUFFE";
  }
}

static void fillPayload(JsonObject root, float t, uint8_t mode) {
  uint8_t m = mode;
  if (m > 5) m = 0;
  switch (m) {
    case 1:
      fillPayloadRoulement(root, t);
      break;
    case 2:
      fillPayloadSurcharge(root, t);
      break;
    case 3:
      fillPayloadElectrique(root, t);
      break;
    case 4:
      fillPayloadUsure(root, t);
      break;
    case 5:
      fillPayloadPression(root, t);
      break;
    default:
      fillPayloadThermalRamp(root, t);
      break;
  }
}

void setupWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("OK IP: ");
  Serial.println(WiFi.localIP());
}

void reconnectMqtt() {
  buildTopic();
  while (!mqtt.connected()) {
    Serial.print("MQTT...");
    String clientId = String("dali_ramp_") + String((uint32_t)millis(), HEX) + String((uint32_t)random(0xffff), HEX);
    if (mqtt.connect(clientId.c_str())) {
      Serial.println("connecte");
    } else {
      Serial.print("echec ");
      Serial.println(mqtt.state());
      delay(3000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  randomSeed(esp_random());
  delay(800);
  buildTopic();
  Serial.println(topicBuf);
  if (CYCLE_ALL_SCENARIOS) {
    Serial.println("Mode: CYCLE 6 scenarios (0=SURCHAUFFE .. 5=PRESSION) apres chaque rampe.");
  } else {
    Serial.print("Mode: scenario fixe ");
    Serial.print(SCENARIO_MODE);
    Serial.print(" = ");
    Serial.println(scenarioName(SCENARIO_MODE));
  }

  if (NODE_PREDICT_URL && NODE_PREDICT_URL[0]) {
    Serial.print("Prediction HTTP: ");
    Serial.println(NODE_PREDICT_URL);
  } else {
    Serial.println("(NODE_PREDICT_URL vide -> pas de % panne sur le Serial, voir dashboard)");
  }

  setupWifi();
  mqtt.setServer(MQTT_SERVER, MQTT_PORT);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    setupWifi();
  }
  if (!mqtt.connected()) {
    reconnectMqtt();
  }
  mqtt.loop();

  static unsigned long last = 0;
  static int step = 0;
  static uint8_t cycleScenario = 0;
  unsigned long now = millis();
  if (now - last < PUBLISH_INTERVAL_MS) {
    return;
  }
  last = now;

  float t = (RAMP_STEPS <= 1) ? 1.f : (float)step / (float)(RAMP_STEPS - 1);

  uint8_t activeMode = CYCLE_ALL_SCENARIOS ? cycleScenario : SCENARIO_MODE;
  if (activeMode > 5) activeMode = 0;

  StaticJsonDocument<2048> doc;
  /* ArduinoJson 6 : pas utiliser doc.to<Json>() (réservé à la v7) */
  deserializeJson(doc, "{}");
  JsonObject root = doc.as<JsonObject>();
  fillPayload(root, t, activeMode);

  char buf[2048];
  size_t n = serializeJson(doc, buf, sizeof(buf));
  if (n == 0 || n >= sizeof(buf)) {
    Serial.println("JSON trop grand (augmenter buf ou simplifier le JSON)");
    return;
  }

  mqtt.loop();
  bool ok = mqtt.publish(topicBuf, buf, false);
  Serial.print("Step ");
  Serial.print(step);
  Serial.print("/");
  Serial.print(RAMP_STEPS - 1);
  Serial.print(" t=");
  Serial.print(t, 2);
  {
    uint8_t m = activeMode;
    const float s = rampS(t);
    Serial.print(" [");
    Serial.print((int)m);
    Serial.print(":");
    switch (m) {
      case 1:
        Serial.print("ROUL");
        Serial.print("] T~");
        Serial.print(50.f + s * 25.f, 0);
        Serial.print(" vib~");
        Serial.print(3.f + s * 5.f, 1);
        break;
      case 2:
        Serial.print("SURCH");
        Serial.print("] T~");
        Serial.print(55.f + s * 30.f, 0);
        Serial.print(" P~");
        Serial.print((120.f + s * 80.f), 0);
        Serial.print("kW");
        break;
      case 3:
        Serial.print("ELEC");
        Serial.print("] T~");
        Serial.print(45.f + s * 40.f, 0);
        break;
      case 4:
        Serial.print("USURE");
        Serial.print("] T~");
        Serial.print(50.f + s * 20.f, 0);
        break;
      case 5:
        Serial.print("PRES");
        Serial.print("] T~");
        Serial.print(55.f + s * 15.f, 0);
        break;
      default:
        Serial.print("THERM");
        Serial.print("] T°C=");
        {
          const float ak = 297.5f + s * 14.0f;
          const float pk = 306.5f + s * 62.0f;
          Serial.print((ak + pk) * 0.5f - 273.15f, 1);
        }
        break;
    }
  }
  Serial.print(ok ? " OK " : " FAIL ");
  Serial.print("json_len=");
  Serial.print((unsigned)strlen(buf));
  Serial.print(" ");
  Serial.println(buf);
  if (!ok) {
    Serial.print("   ! publish MQTT refuse (buffer interne < MQTT_MAX_PACKET_SIZE ou deconnecte). mqtt.state()=");
    Serial.println(mqtt.state());
  }

  printPredictionFromBackend(buf);

  step++;
  if (step >= RAMP_STEPS) {
    step = 0;
    if (CYCLE_ALL_SCENARIOS) {
      cycleScenario = (uint8_t)((cycleScenario + 1) % 6);
      Serial.print(">>> Scenario suivant: ");
      Serial.print((int)cycleScenario);
      Serial.print(" = ");
      Serial.println(scenarioName(cycleScenario));
    }
    Serial.println("--- Nouveau cycle rampe ---");
  }
}
