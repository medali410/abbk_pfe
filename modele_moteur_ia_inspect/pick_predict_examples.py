#!/usr/bin/env python3
"""
Sélectionne 3 lignes du CSV AI4I (normal / surveillance / critique) selon le
XGBoost déjà entraîné, et écrit iot-backend/examples_predict_tabular.json
(corps prêts pour POST /api/predict).

Usage (depuis la racine du repo) :
  python modele_moteur_ia_inspect/pick_predict_examples.py
  python modele_moteur_ia_inspect/pick_predict_examples.py --csv iot-backend/ai4i2020.csv
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

_MOD_DIR = Path(__file__).resolve().parent
if str(_MOD_DIR) not in sys.path:
    sys.path.insert(0, str(_MOD_DIR))
import train_tabular as _tt

_build_xy = _tt._build_xy
_find_default_csv = _tt._find_default_csv

TYPE_TO_API = {"L": "EL_S", "M": "EL_M", "H": "EL_L"}


def _row_to_payload(df_raw: pd.DataFrame, idx: int, profile: str, machine_id: str) -> dict:
    r = df_raw.iloc[idx]
    t = str(r["Type"]).strip().upper()[0]
    type_moteur = TYPE_TO_API.get(t, "EL_M")
    return {
        "profile": profile,
        "machineId": machine_id,
        "type_moteur": type_moteur,
        "air_temperature": float(r["Air temperature [K]"]),
        "process_temperature": float(r["Process temperature [K]"]),
        "rpm": float(r["Rotational speed [rpm]"]),
        "torque": float(r["Torque [Nm]"]),
        "tool_wear": float(r["Tool wear [min]"]),
        "presence": 1.0,
        "magnetic": 0.6,
    }


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", type=Path, default=None)
    ap.add_argument(
        "--models",
        type=Path,
        default=repo_root / "modele_moteur_ia_inspect" / "models_tabular",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=repo_root / "iot-backend" / "examples_predict_tabular.json",
    )
    args = ap.parse_args()
    csv_path = args.csv or _find_default_csv(repo_root)
    if csv_path is None or not csv_path.exists():
        print("CSV introuvable. Utilisez --csv ou placez iot-backend/ai4i2020.csv", file=sys.stderr)
        return 1
    for name in ("xgb_panne.pkl", "scaler_tabular.pkl"):
        if not (args.models / name).exists():
            print(f"Artefact manquant: {args.models / name}", file=sys.stderr)
            return 1

    df_raw = pd.read_csv(csv_path)
    X, y = _build_xy(df_raw)
    scaler = joblib.load(args.models / "scaler_tabular.pkl")
    xgb = joblib.load(args.models / "xgb_panne.pkl")
    Xs = scaler.transform(X.values.astype(np.float64))
    p = xgb.predict_proba(Xs)[:, 1]

    ok = y == 0
    i_normal = int(np.argmin(p[ok]))
    i_normal = int(np.where(ok)[0][i_normal])

    i_surv = int(np.argmin(np.abs(p[ok] - 0.45)))
    i_surv = int(np.where(ok)[0][i_surv])

    fail = y == 1
    if not fail.any():
        print("Aucune panne (y=1) dans le CSV.", file=sys.stderr)
        return 1
    i_crit = int(np.argmax(p[fail]))
    i_crit = int(np.where(fail)[0][i_crit])

    examples = [
        _row_to_payload(df_raw, i_normal, "normal", "TEST_NORMAL"),
        _row_to_payload(df_raw, i_surv, "surveillance", "TEST_SURVEILLANCE"),
        _row_to_payload(df_raw, i_crit, "critique", "TEST_CRITIQUE"),
    ]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(examples, indent=2), encoding="utf-8")

    print(f"[pick_predict_examples] écrit: {args.out}")
    for ex, idx in zip(examples, (i_normal, i_surv, i_crit)):
        udi = df_raw.iloc[idx]["UDI"] if "UDI" in df_raw.columns else "?"
        print(f"  {ex['profile']:12} idx={idx} prob_panne~={100*p[idx]:.1f}% UDI={udi}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
