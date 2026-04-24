"""
DALI IA Inference Service  v2.0

Modes:
  - Par défaut: LSTM (+ autoencodeur optionnel) comme avant.
  - USE_TABULAR=1: XGBoost (probabilité panne) + Isolation Forest (anomalie),
    artefacts dans TABULAR_ARTIFACTS_DIR (voir train_tabular.py).
"""

from __future__ import annotations

import json
import os
from collections import deque
from pathlib import Path
from typing import Any, Dict, List, Optional

import joblib
import numpy as np
import tensorflow as tf
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Paths & mode tabulaire
# ---------------------------------------------------------------------------

def _first_existing(paths: List[Path]) -> Path:
    for p in paths:
        if p.exists():
            return p
    raise FileNotFoundError(f"No artifacts directory found among: {paths}")


def _first_file(paths: List[Path]) -> Path:
    for p in paths:
        if p.exists():
            return p
    raise FileNotFoundError(f"Required artifact not found among: {paths}")


def _load_json(path: Path) -> Dict:
    return json.loads(path.read_text(encoding="utf-8"))


BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent.parent

USE_TABULAR = os.getenv("USE_TABULAR", "").strip().lower() in ("1", "true", "yes")
TABULAR_DIR = Path(
    os.getenv(
        "TABULAR_ARTIFACTS_DIR",
        str(PROJECT_ROOT / "modele_moteur_ia_inspect" / "models_tabular"),
    )
)

if USE_TABULAR:
    ARTIFACTS_DIR = TABULAR_DIR
else:
    ARTIFACTS_DIR = Path(
        os.getenv(
            "MODEL_ARTIFACTS_DIR",
            str(
                _first_existing([
                    PROJECT_ROOT / "modele_moteur_ia_inspect" / "models_v3_lstm",
                    PROJECT_ROOT / "modele_moteur_ia_inspect" / "models_v2_step4",
                    PROJECT_ROOT / "modele_moteur_ia_inspect" / "models_v2_over",
                    PROJECT_ROOT / "modele_moteur_ia_inspect" / "models_v2",
                    PROJECT_ROOT / "modele_moteur_ia_inspect" / "models",
                ])
            ),
        )
    )

# Per-machine ring-buffers (LSTM windowing)
_buffers: Dict[str, deque] = {}

# --- Tabulaire (XGB + Isolation Forest) ---
TB: Optional[Dict[str, Any]] = None

# --- LSTM / Keras ---
metadata: Dict = {}
scaler = None
le_type = None
le_scenario = None
model = None
MODEL_VERSION = "legacy"
IS_LSTM = False
WINDOW_SIZE = 1
CAPTEURS_BASE = [
    "temperature", "pression", "puissance", "vibration",
    "presence", "magnetique", "infrarouge",
]
CAPTEURS: List[str] = list(CAPTEURS_BASE)
RUL_MAX = 1.0
ae_model = None
ae_threshold = 0.0

if USE_TABULAR:
    req = [
        TABULAR_DIR / "metadata_tabular.json",
        TABULAR_DIR / "scaler_tabular.pkl",
        TABULAR_DIR / "xgb_panne.pkl",
        TABULAR_DIR / "iso_forest.pkl",
    ]
    missing = [str(p) for p in req if not p.exists()]
    if missing:
        raise FileNotFoundError(
            "USE_TABULAR=1 mais artefacts manquants: "
            + ", ".join(missing)
            + " — lancez: python modele_moteur_ia_inspect/train_tabular.py --csv .../ai4i2020.csv"
        )
    tmeta = _load_json(TABULAR_DIR / "metadata_tabular.json")
    TB = {
        "meta": tmeta,
        "scaler": joblib.load(TABULAR_DIR / "scaler_tabular.pkl"),
        "xgb": joblib.load(TABULAR_DIR / "xgb_panne.pkl"),
        "iso": joblib.load(TABULAR_DIR / "iso_forest.pkl"),
        "iso_threshold": float(tmeta.get("iso_threshold", 0.0)),
        "features": list(tmeta.get("feature_columns", [])),
    }
    MODEL_VERSION = str(tmeta.get("version", "tabular"))
    metadata = tmeta
    print(f"[inference_api] mode=TABULAR_XGB_ISO version={MODEL_VERSION} dir={TABULAR_DIR}")
else:
    metadata = _load_json(ARTIFACTS_DIR / "metadata.json")
    scaler = joblib.load(ARTIFACTS_DIR / "scaler.pkl")
    le_type = joblib.load(_first_file([ARTIFACTS_DIR / "le_type.pkl", ARTIFACTS_DIR / "le_type_moteur.pkl"]))
    le_scenario = joblib.load(ARTIFACTS_DIR / "le_scenario.pkl")

    model_path = _first_file([
        ARTIFACTS_DIR / "best_model_v3.keras",
        ARTIFACTS_DIR / "best_model_v2.keras",
        ARTIFACTS_DIR / "best_model.keras",
        ARTIFACTS_DIR / "model_universel.keras",
    ])
    model = tf.keras.models.load_model(model_path, compile=False)

    MODEL_VERSION = metadata.get("version", "legacy")
    IS_LSTM = metadata.get("model_type") == "lstm"
    WINDOW_SIZE = int(metadata.get("window_size", 1))
    CAPTEURS = metadata.get("capteurs", CAPTEURS_BASE)
    RUL_MAX = float(metadata.get("rul_max", 1.0))

    ae_path = ARTIFACTS_DIR / "autoencoder.keras"
    ae_metrics_path = ARTIFACTS_DIR / "autoencoder_metrics.json"
    if ae_path.exists():
        ae_model = tf.keras.models.load_model(ae_path, compile=False)
        if ae_metrics_path.exists():
            ae_meta = _load_json(ae_metrics_path)
            ae_threshold = float(ae_meta.get("threshold", 0.01))

    print(
        f"[inference_api] model={MODEL_VERSION}, lstm={IS_LSTM}, window={WINDOW_SIZE}, "
        f"autoencoder={'loaded' if ae_model else 'none'}, artifacts={ARTIFACTS_DIR}"
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _map_machine_type(raw: str) -> str:
    t = (raw or "EL_M").upper()
    if le_type is not None and t in le_type.classes_:
        return t
    compact = {"L": "EL_S", "M": "EL_M", "H": "EL_L"}
    return compact.get(t, "EL_M")


def _feature_dict(inp: "PredictInput") -> Dict[str, float]:
    rpm_safe = max(inp.rpm, 1.0)
    max_wear = max(inp.max_wear_reference, 1.0)
    base = {
        "temperature": inp.temperature,
        "pression": inp.pression if inp.pression is not None else (inp.torque / rpm_safe),
        "puissance": inp.puissance if inp.puissance is not None else (inp.torque * inp.rpm),
        "vibration": inp.vibration if inp.vibration is not None else (inp.rpm / 1000.0),
        "presence": inp.presence,
        "magnetique": inp.magnetique,
        "infrarouge": inp.infrarouge if inp.infrarouge is not None else inp.process_temperature,
    }
    if len(CAPTEURS) > 7:
        base["delta_temp"] = inp.process_temperature - inp.air_temperature
        base["power_norm"] = (inp.torque * inp.rpm) / rpm_safe
        base["wear_ratio"] = min(max(inp.tool_wear / max_wear, 0.0), 1.0)
        base["torque_per_rpm"] = inp.torque / rpm_safe
    return base


def _get_buffer(machine_id: str) -> deque:
    if machine_id not in _buffers:
        _buffers[machine_id] = deque(maxlen=WINDOW_SIZE)
    return _buffers[machine_id]


def _build_window(machine_id: str, features_vec: np.ndarray) -> np.ndarray:
    buf = _get_buffer(machine_id)
    buf.append(features_vec.copy())
    arr = list(buf)
    while len(arr) < WINDOW_SIZE:
        arr.insert(0, arr[0].copy())
    window = np.array(arr[-WINDOW_SIZE:], dtype=np.float32)
    return window.reshape(1, WINDOW_SIZE, -1)


def _type_moteur_to_ord(raw: str) -> int:
    t = (raw or "EL_M").upper()
    if t.startswith("EL_S") or t == "L":
        return 0
    if t.startswith("EL_L") or t == "H":
        return 2
    return 1


def _tabular_feature_row(inp: PredictInput) -> np.ndarray:
    assert TB is not None
    rpm_s = max(float(inp.rpm), 1.0)
    type_ord = _type_moteur_to_ord(inp.type_moteur)
    delta = float(inp.process_temperature) - float(inp.air_temperature)
    pression = float(inp.pression) if inp.pression is not None else (float(inp.torque) / rpm_s)
    puissance = float(inp.puissance) if inp.puissance is not None else (float(inp.torque) * float(inp.rpm))
    vibration = float(inp.vibration) if inp.vibration is not None else (float(inp.rpm) / 1000.0)
    row = [
        float(inp.air_temperature),
        float(inp.process_temperature),
        float(inp.torque),
        float(inp.rpm),
        float(inp.tool_wear),
        float(type_ord),
        delta,
        pression,
        puissance,
        vibration,
        float(inp.presence),
        float(inp.magnetique),
    ]
    feats = TB["features"]
    if len(row) != len(feats):
        raise ValueError(f"Feature count mismatch: got {len(row)}, metadata expects {len(feats)}")
    return np.array(row, dtype=np.float64).reshape(1, -1)


def _predict_tabular(payload: PredictInput) -> Dict[str, Any]:
    assert TB is not None
    x_raw = _tabular_feature_row(payload)
    x_s = TB["scaler"].transform(x_raw)
    panne_p = float(TB["xgb"].predict_proba(x_s)[0, 1])
    iso_dec = float(TB["iso"].decision_function(x_s)[0])
    thr = TB["iso_threshold"]
    ae_is_anomaly = iso_dec < thr
    ae_anomaly_score = round(float(-iso_dec), 6)

    if ae_is_anomaly:
        boost = min(0.15, max(0.0, (thr - iso_dec) / max(abs(thr), 1e-3) * 0.05))
        panne_p = min(1.0, panne_p + boost)

    anomalie_p = 0.85 if ae_is_anomaly else min(0.35, panne_p * 0.5)
    rul_estime = round((1.0 - panne_p) * 100.0, 2)
    scen_label = "Risque_tabulaire" if panne_p >= 0.5 else "Normal"

    return {
        "machineId": payload.machineId,
        "model_version": MODEL_VERSION,
        "panne_probability": panne_p,
        "anomalie_probability": anomalie_p,
        "rul_estime": rul_estime,
        "scenario_label": scen_label,
        "scenario_confidence": round(max(panne_p, 1.0 - panne_p), 4),
        "prediction": 1 if panne_p >= 0.5 else 0,
        "prob_panne": round(panne_p * 100.0, 2),
        "niveau": (
            "CRITIQUE" if panne_p >= 0.8
            else "ELEVE" if panne_p >= 0.6
            else "SURVEILLANCE" if panne_p >= 0.4
            else "NORMAL"
        ),
        "panne_type": scen_label,
        "ae_anomaly_score": ae_anomaly_score,
        "ae_is_anomaly": ae_is_anomaly,
        "ae_threshold": thr,
    }


# ---------------------------------------------------------------------------
# Pydantic input
# ---------------------------------------------------------------------------


class SensorReading(BaseModel):
    temperature: float = 25.0
    pression: float | None = None
    puissance: float | None = None
    vibration: float | None = None
    presence: float = 1.0
    magnetique: float = 0.6
    infrarouge: float | None = None


class PredictInput(BaseModel):
    machineId: str = "MAC_A01"
    type_moteur: str = "EL_M"

    temperature: float = 25.0
    pression: float | None = None
    puissance: float | None = None
    vibration: float | None = None
    presence: float = 1.0
    magnetique: float = 0.6
    infrarouge: float | None = None

    air_temperature: float = 298.0
    process_temperature: float = 303.0
    torque: float = 40.0
    rpm: float = 1500.0
    tool_wear: float = 50.0
    max_wear_reference: float = Field(default=250.0, ge=1.0)

    window: Optional[List[SensorReading]] = None


# ---------------------------------------------------------------------------
# FastAPI
# ---------------------------------------------------------------------------

app = FastAPI(title="DALI IA Inference Service", version="2.0.0")


@app.get("/api/health")
def health():
    if USE_TABULAR and TB is not None:
        return {
            "status": "ok",
            "model_version": MODEL_VERSION,
            "mode": "tabular_xgb_iso",
            "window_size": 1,
            "autoencoder": False,
            "artifacts_dir": str(TABULAR_DIR),
            "feature_columns": TB["features"],
        }
    return {
        "status": "ok",
        "model_version": MODEL_VERSION,
        "is_lstm": IS_LSTM,
        "window_size": WINDOW_SIZE,
        "autoencoder": ae_model is not None,
        "artifacts_dir": str(ARTIFACTS_DIR),
        "capteurs": CAPTEURS,
    }


@app.post("/api/predict")
def predict(payload: PredictInput):
    try:
        if USE_TABULAR and TB is not None:
            return _predict_tabular(payload)

        fdict = _feature_dict(payload)
        mapped_type = _map_machine_type(payload.type_moteur)
        x_type = le_type.transform([mapped_type]).astype(np.int32)

        if IS_LSTM:
            base_vec = np.array([float(fdict.get(c, 0.0)) for c in CAPTEURS_BASE], dtype=np.float32)
            scaled_vec = scaler.transform(base_vec.reshape(1, -1)).reshape(-1).astype(np.float32)
            x_window = _build_window(payload.machineId, scaled_vec)

            pred_panne, pred_rul, pred_anomalie, pred_scenario = model.predict(
                {"capteurs_seq": x_window, "type_moteur": x_type}, verbose=0,
            )
        else:
            x = np.array([[float(fdict.get(c, 0.0)) for c in CAPTEURS]], dtype=np.float32)
            x_scaled = scaler.transform(x).astype(np.float32)
            pred_panne, pred_rul, pred_anomalie, pred_scenario = model.predict(
                {"capteurs": x_scaled, "type_moteur": x_type}, verbose=0,
            )

        panne_probability = float(pred_panne.reshape(-1)[0])
        anomalie_probability = float(pred_anomalie.reshape(-1)[0])
        rul_estime = float(pred_rul.reshape(-1)[0] * RUL_MAX)
        scen_idx = int(np.argmax(pred_scenario, axis=1)[0])
        scen_label = str(le_scenario.inverse_transform([scen_idx])[0])
        scen_conf = float(np.max(pred_scenario, axis=1)[0])

        ae_anomaly_score = 0.0
        ae_is_anomaly = False
        if ae_model is not None and IS_LSTM:
            base_only = np.array([float(fdict.get(c, 0.0)) for c in CAPTEURS_BASE], dtype=np.float32)
            base_scaled = scaler.transform(base_only.reshape(1, -1)).reshape(-1).astype(np.float32)
            buf = _get_buffer(payload.machineId)
            ae_buf = list(buf)
            while len(ae_buf) < WINDOW_SIZE:
                ae_buf.insert(0, ae_buf[0].copy() if ae_buf else base_scaled.copy())
            ae_window = np.array(ae_buf[-WINDOW_SIZE:], dtype=np.float32)
            n_feats_ae = ae_model.input_shape[-1]
            ae_window = ae_window[:, :n_feats_ae]
            ae_input = ae_window.reshape(1, WINDOW_SIZE, n_feats_ae)
            ae_recon = ae_model.predict(ae_input, verbose=0)
            ae_anomaly_score = float(np.mean((ae_input - ae_recon) ** 2))
            ae_is_anomaly = ae_anomaly_score > ae_threshold

        if ae_is_anomaly:
            boost = min(0.2, ae_anomaly_score / max(ae_threshold, 1e-6) * 0.1)
            panne_probability = min(1.0, panne_probability + boost)
            anomalie_probability = min(1.0, anomalie_probability + boost)

        return {
            "machineId": payload.machineId,
            "model_version": MODEL_VERSION,
            "panne_probability": panne_probability,
            "anomalie_probability": anomalie_probability,
            "rul_estime": rul_estime,
            "scenario_label": scen_label,
            "scenario_confidence": scen_conf,
            "prediction": 1 if panne_probability >= 0.5 else 0,
            "prob_panne": round(panne_probability * 100.0, 2),
            "niveau": (
                "CRITIQUE" if panne_probability >= 0.8
                else "ELEVE" if panne_probability >= 0.6
                else "SURVEILLANCE" if panne_probability >= 0.4
                else "NORMAL"
            ),
            "panne_type": scen_label,
            "ae_anomaly_score": round(ae_anomaly_score, 6),
            "ae_is_anomaly": ae_is_anomaly,
            "ae_threshold": ae_threshold,
        }

    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Inference failed: {exc}") from exc
