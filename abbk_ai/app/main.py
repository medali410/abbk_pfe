"""
ABBK Predictive Maintenance - Microservice IA
Modèle : LSTM v3 kaggle3 (local)
Scénarios : NORMAL / SURCHAUFFE / SURCHARGE / 
            ELECTRIQUE / ROULEMENT / USURE_GENERALE
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional
import numpy as np
import joblib
import json
import logging
import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
import tensorflow as tf

# ─── Logging ────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ─── App ────────────────────────────────────────────────────
app = FastAPI(
    title="ABBK AI Predictive Maintenance",
    description="Microservice IA — détection de pannes industrielles",
    version="2.0.0"
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Chemins modèles ────────────────────────────────────────
BASE_DIR    = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR  = os.path.join(BASE_DIR, "..", "models")

# ─── Variables globales ─────────────────────────────────────
MODEL       = None
SCALER      = None
LE_SCENARIO = None
LE_TYPE     = None
METADATA    = None
WINDOW_SIZE = 10

# ─── Diagnostics par scénario ───────────────────────────────
DIAGNOSTICS = {
    "NORMAL": {
        "message"      : "✅ Machine en bon état de fonctionnement.",
        "recommandation": "Aucune action requise. Continuer la surveillance.",
        "urgence"       : "faible"
    },
    "SURCHAUFFE": {
        "message"      : "🌡️ Température anormalement élevée détectée.",
        "recommandation": "Vérifier le système de refroidissement. "
                          "Réduire la charge si possible.",
        "urgence"       : "haute"
    },
    "SURCHARGE": {
        "message"      : "⚡ Surcharge électrique détectée — "
                          "courant et puissance hors limites.",
        "recommandation": "Réduire immédiatement la charge machine. "
                          "Vérifier l'alimentation électrique.",
        "urgence"       : "haute"
    },
    "ELECTRIQUE": {
        "message"      : "🔌 Anomalie électrique détectée — "
                          "variation de tension ou de fréquence.",
        "recommandation": "Inspecter le câblage et les connexions. "
                          "Contacter un électricien.",
        "urgence"       : "moyenne"
    },
    "ROULEMENT": {
        "message"      : "🔧 Vibrations anormales — "
                          "usure probable des roulements.",
        "recommandation": "Planifier une inspection mécanique. "
                          "Vérifier les roulements et l'alignement.",
        "urgence"       : "moyenne"
    },
    "USURE_GENERALE": {
        "message"      : "📉 Dégradation progressive détectée — "
                          "usure générale de la machine.",
        "recommandation": "Programmer une maintenance préventive "
                          "dans les prochains jours.",
        "urgence"       : "moyenne"
    }
}


# ─── Chargement des modèles ─────────────────────────────────
def load_models():
    global MODEL, SCALER, LE_SCENARIO, LE_TYPE, METADATA, WINDOW_SIZE
    try:
        logger.info("Chargement des modèles LSTM...")

        MODEL = tf.keras.models.load_model(
            os.path.join(MODELS_DIR, "best_model_v3.keras"),
            compile=False
        )
        SCALER      = joblib.load(os.path.join(MODELS_DIR, "scaler.pkl"))
        LE_SCENARIO = joblib.load(os.path.join(MODELS_DIR, "le_scenario.pkl"))
        LE_TYPE     = joblib.load(os.path.join(MODELS_DIR, "le_type.pkl"))

        with open(os.path.join(MODELS_DIR, "metadata.json"), "r") as f:
            METADATA = json.load(f)

        WINDOW_SIZE = METADATA.get("window_size", 10)
        logger.info(f"✅ Modèles chargés — window_size={WINDOW_SIZE}")

    except Exception as e:
        logger.error(f"❌ Erreur chargement: {e}")
        raise


@app.on_event("startup")
async def startup_event():
    load_models()


# ─── Schémas ────────────────────────────────────────────────
class SensorData(BaseModel):
    machine_id: str = Field(..., example="MAC_VERIN_001")

    # Capteurs ABBK
    temperature_contact:    float = Field(..., example=45.2,
                                description="DS18B20 (°C)")
    temperature_infrarouge: float = Field(..., example=48.7,
                                description="MLX90614 (°C)")
    vibration_x:            float = Field(..., example=0.12,
                                description="ADXL345 X (g)")
    vibration_y:            float = Field(..., example=0.08,
                                description="ADXL345 Y (g)")
    courant:                float = Field(..., example=3.5,
                                description="PZEM courant (A)")
    puissance:              float = Field(..., example=750.0,
                                description="PZEM puissance (W)")

    # Optionnels
    tension:     Optional[float] = Field(None, example=220.0)
    vibration_z: Optional[float] = Field(None, example=0.02)
    frequence:   Optional[float] = Field(None, example=50.0)
    pression:    Optional[float] = Field(None, example=2.5)

    # Type machine
    machine_type: Optional[str] = Field("M", example="M",
                                description="L / M / H")

    # Historique optionnel
    history: Optional[list] = Field(default_factory=list, description="Tableau historique des 10 dernières valeurs")


class PredictionResult(BaseModel):
    machine_id:       str
    status:           str    # Normal | Warning | Critical
    risk_percentage:  int
    type_panne:       str    # NORMAL | SURCHAUFFE | ...
    diagnostic:       str
    recommandation:   str
    urgence:          str
    details:          dict


# ─── Utilitaires ────────────────────────────────────────────
TYPE_ORD_MAP = {"L": 0, "M": 1, "H": 2}

def status_from_scenario(scenario: str, risk: float) -> str:
    if scenario == "NORMAL" and risk < 0.4:
        return "Normal"
    elif risk >= 0.7 or scenario in ("SURCHAUFFE", "SURCHARGE"):
        return "Critical"
    else:
        return "Warning"


def build_feature_vector(data: SensorData) -> np.ndarray:
    """
    Construit le vecteur de features dans l'ordre exact
    attendu par le scaler : 7 features
    temperature, pression, puissance, vibration, presence, magnetique, infrarouge
    """
    vibration = float(np.sqrt(
        data.vibration_x**2 + data.vibration_y**2
    ))
    
    # Estimation des paramètres physiques pour dériver la pression si non fournie
    rpm_est = vibration * 1000
    torque_est = (data.puissance / (rpm_est + 1e-5)) * 9.549
    
    if data.pression is not None:
        pression = data.pression
    else:
        pression = torque_est / max(rpm_est, 1.0)
        
    # magnetique mappé depuis le type de machine
    m_type = (data.machine_type or "M").upper()
    if m_type == "L":
        magnetique = 0.3
    elif m_type == "M":
        magnetique = 0.6
    elif m_type == "H":
        magnetique = 0.9
    else:
        magnetique = 0.5

    features = np.array([[
        (data.temperature_contact + data.temperature_infrarouge) / 2.0, # temperature
        pression,                                                      # pression
        data.puissance,                                                # puissance
        vibration,                                                     # vibration
        1.0,                                                           # presence
        magnetique,                                                    # magnetique
        data.temperature_infrarouge                                    # infrarouge
    ]])
    return features


def build_feature_vector_from_dict(h: dict, fallback: SensorData) -> list:
    tc = float(h.get('temperature_contact') or h.get('temperature') or fallback.temperature_contact)
    ti = float(h.get('temperature_infrarouge') or h.get('infrared') or h.get('temperature') or fallback.temperature_infrarouge)
    vx = float(h.get('vibration_x') or h.get('vibration') or fallback.vibration_x)
    vy = float(h.get('vibration_y') or 0.0)
    pwr = float(h.get('puissance') or h.get('powerConsumption') or h.get('power') or fallback.puissance)
    press = h.get('pression') or h.get('pressure') or fallback.pression
    
    vibration = float(np.sqrt(vx**2 + vy**2))
    rpm_est = vibration * 1000
    torque_est = (pwr / (rpm_est + 1e-5)) * 9.549
    
    if press is not None:
        pression = float(press)
    else:
        pression = torque_est / max(rpm_est, 1.0)
        
    m_type = (fallback.machine_type or "M").upper()
    if m_type == "L": magnetique = 0.3
    elif m_type == "M": magnetique = 0.6
    elif m_type == "H": magnetique = 0.9
    else: magnetique = 0.5

    return [(tc + ti) / 2.0, pression, pwr, vibration, 1.0, magnetique, ti]


def build_window(features_scaled: np.ndarray) -> np.ndarray:
    """
    Répliquer le vecteur WINDOW_SIZE fois
    pour simuler une fenêtre temporelle.
    Shape : (1, WINDOW_SIZE, n_features)
    """
    window = np.repeat(features_scaled, WINDOW_SIZE, axis=0)
    return window.reshape(1, WINDOW_SIZE, -1)


# ─── Endpoints ──────────────────────────────────────────────
@app.get("/")
def root():
    return {
        "service" : "ABBK AI Predictive Maintenance",
        "version" : "2.0.0",
        "model"   : "LSTM v3 — AI4I dataset",
        "scenarios": list(DIAGNOSTICS.keys())
    }


@app.get("/health")
def health():
    return {
        "status"      : "ok",
        "model_loaded": MODEL is not None,
        "window_size" : WINDOW_SIZE
    }


@app.post("/predict", response_model=PredictionResult)
def predict(data: SensorData):
    if MODEL is None:
        raise HTTPException(503, "Modèle non disponible")

    try:
        # 1. Features
        if data.history and len(data.history) > 0:
            history_vectors = [build_feature_vector_from_dict(h, data) for h in data.history]
            while len(history_vectors) < WINDOW_SIZE:
                history_vectors.insert(0, history_vectors[0])
            if len(history_vectors) > WINDOW_SIZE:
                history_vectors = history_vectors[-WINDOW_SIZE:]
            history_features = np.array(history_vectors)
            features_sc = SCALER.transform(history_features)
            window = features_sc.reshape(1, WINDOW_SIZE, -1)
        else:
            features     = build_feature_vector(data)
            features_sc  = SCALER.transform(features)
            window       = build_window(features_sc)

        # Encodage du type de moteur pour l'entrée 'type_moteur' du modèle
        m_type = (data.machine_type or "M").upper()
        type_mapping = {"L": "EL_S", "M": "EL_M", "H": "EL_L"}
        type_str = type_mapping.get(m_type, "EL_M")
        
        try:
            encoded_type = LE_TYPE.transform([type_str])[0]
        except Exception:
            encoded_type = LE_TYPE.transform(["EL_M"])[0]
            
        type_input = np.array([[encoded_type]], dtype=np.int32) # Shape (1, 1)

        # 2. Prédiction (modèle multi-entrées, 4 sorties)
        outputs      = MODEL.predict({"capteurs_seq": window, "type_moteur": type_input}, verbose=0)

        # Le modèle retourne 4 sorties :
        # [panne_proba, rul, anomalie_proba, scenario_proba]
        panne_proba    = float(outputs[0][0][0])
        rul            = float(outputs[1][0][0])
        anomalie_proba = float(outputs[2][0][0])
        scenario_proba = outputs[3][0]

        # 3. Scénario
        scenario_idx  = int(np.argmax(scenario_proba))
        scenario_name = LE_SCENARIO.inverse_transform(
                            [scenario_idx]
                        )[0]

        # 4. Statut
        risk_pct = int(panne_proba * 100)
        status   = status_from_scenario(scenario_name, panne_proba)

        # 5. Diagnostic
        diag = DIAGNOSTICS.get(
            scenario_name, DIAGNOSTICS["NORMAL"]
        )

        # 6. Détails
        vibration_val = float(np.sqrt(data.vibration_x**2 + data.vibration_y**2))
        avg_temp = (data.temperature_contact + data.temperature_infrarouge) / 2.0

        # Risque chauffage: <30 = normal (0-30%), 30-50 = risque (30-60%), >50 = danger (60-100%)
        if avg_temp <= 30:
            heat_risk = int((avg_temp / 30.0) * 30)
        elif avg_temp <= 50:
            heat_risk = int(30 + ((avg_temp - 30) / 20.0) * 30)
        else:
            heat_risk = int(60 + ((avg_temp - 50) / 50.0) * 40)
        heat_risk = max(0, min(100, heat_risk))

        # Risque vibration: <7 = normal (0-35%), 7-12 = risque (35-65%), >12 = danger (65-100%)
        vib_mm_s = vibration_val * 50  # conversion g -> mm/s approximative
        if vib_mm_s <= 7:
            vib_risk = int((vib_mm_s / 7.0) * 35)
        elif vib_mm_s <= 12:
            vib_risk = int(35 + ((vib_mm_s - 7) / 5.0) * 30)
        else:
            vib_risk = int(65 + ((vib_mm_s - 12) / 8.0) * 35)
        vib_risk = max(0, min(100, vib_risk))

        details = {
            "panne_probability"  : round(panne_proba, 4),
            "anomalie_probability" : round(anomalie_proba, 4),
            "rul_cycles"         : max(0, round(rul, 1)),
            "heat_risk"          : heat_risk,
            "vibration_risk"     : vib_risk,
            "scenario_scores"    : {
                LE_SCENARIO.inverse_transform([i])[0]: round(float(p), 3)
                for i, p in enumerate(scenario_proba)
            },
            "features_used"      : {
                "temperature_contact"    : data.temperature_contact,
                "temperature_infrarouge" : data.temperature_infrarouge,
                "vibration_totale_g"     : round(float(vibration_val), 3),
                "courant_A"              : data.courant,
                "puissance_W"            : data.puissance,
            }
        }

        logger.info(
            f"[{data.machine_id}] "
            f"Scénario={scenario_name} | "
            f"Risque={risk_pct}% | "
            f"RUL={rul:.0f}"
        )

        return PredictionResult(
            machine_id      = data.machine_id,
            status          = status,
            risk_percentage = risk_pct,
            type_panne      = scenario_name,
            diagnostic      = diag["message"],
            recommandation  = diag["recommandation"],
            urgence         = diag["urgence"],
            details         = details
        )

    except Exception as e:
        logger.error(f"Erreur: {e}")
        raise HTTPException(500, str(e))
