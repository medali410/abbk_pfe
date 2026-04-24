#!/usr/bin/env python3
"""
Entraîne XGBoost (probabilité de panne) + Isolation Forest (anomalie)
sur le dataset AI4I 2020, avec des features alignées sur PredictInput / buildMlPayload.

Usage:
  python train_tabular.py --csv path/to/ai4i2020.csv
  python train_tabular.py   # cherche ai4i2020.csv sous iot-backend/ puis la racine du repo

Sortie (défaut): modele_moteur_ia_inspect/models_tabular/
  - scaler_tabular.pkl
  - xgb_panne.pkl
  - iso_forest.pkl
  - metadata_tabular.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier


FEATURE_COLUMNS = [
    "air_temperature",
    "process_temperature",
    "torque",
    "rpm",
    "tool_wear",
    "type_ord",
    "delta_temp",
    "pression",
    "puissance",
    "vibration",
    "presence",
    "magnetique",
]

TYPE_ORD = {"L": 0, "M": 1, "H": 2}


def _find_default_csv(repo_root: Path) -> Path | None:
    for rel in (
        Path("iot-backend") / "ai4i2020.csv",
        Path("ai4i2020.csv"),
    ):
        p = repo_root / rel
        if p.exists():
            return p
    return None


def _normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df.columns = [c.strip() for c in df.columns]
    colmap = {}
    for c in df.columns:
        key = c.lower().replace(" ", "_")
        colmap[c] = key
    df = df.rename(columns=colmap)
    return df


def _build_xy(df_raw: pd.DataFrame) -> tuple[pd.DataFrame, np.ndarray]:
    df = _normalize_columns(df_raw)

    type_col = None
    for cand in ("type", "product_type"):
        if cand in df.columns:
            type_col = cand
            break
    if type_col is None:
        raise ValueError("Colonne 'Type' introuvable dans le CSV AI4I.")

    air = None
    proc = None
    rpm = None
    torque = None
    wear = None
    ycol = None
    for name, variants in [
        ("air", ["air_temperature_[k]", "air_temperature_k"]),
        ("proc", ["process_temperature_[k]", "process_temperature_k"]),
        ("rpm", ["rotational_speed_[rpm]", "rotational_speed_rpm"]),
        ("torque", ["torque_[nm]", "torque_nm"]),
        ("wear", ["tool_wear_[min]", "tool_wear_min"]),
        ("y", ["machine_failure"]),
    ]:
        for v in variants:
            if v in df.columns:
                if name == "air":
                    air = df[v]
                elif name == "proc":
                    proc = df[v]
                elif name == "rpm":
                    rpm = df[v]
                elif name == "torque":
                    torque = df[v]
                elif name == "wear":
                    wear = df[v]
                elif name == "y":
                    ycol = df[v].astype(int).values
                break
    if any(x is None for x in (air, proc, rpm, torque, wear)) or ycol is None:
        raise ValueError(
            "Colonnes AI4I attendues manquantes. "
            "Vérifiez le fichier (Air/Process temperature, RPM, Torque, Tool wear, Machine failure)."
        )

    tord = (
        df[type_col]
        .astype(str)
        .str.strip()
        .str.upper()
        .str[0]
        .map(TYPE_ORD)
        .fillna(1)
        .astype(int)
    )

    rpm_safe = rpm.replace(0, np.nan).fillna(1500.0)
    delta = proc - air
    pression = torque / rpm_safe
    puissance = torque * rpm_safe
    vibration = rpm_safe / 1000.0
    presence = np.ones(len(df), dtype=float)
    magnetique = np.full(len(df), 0.6, dtype=float)

    X = pd.DataFrame(
        {
            "air_temperature": air.astype(float),
            "process_temperature": proc.astype(float),
            "torque": torque.astype(float),
            "rpm": rpm_safe.astype(float),
            "tool_wear": wear.astype(float),
            "type_ord": tord,
            "delta_temp": delta.astype(float),
            "pression": pression.astype(float),
            "puissance": puissance.astype(float),
            "vibration": vibration.astype(float),
            "presence": presence,
            "magnetique": magnetique,
        }
    )
    return X.reindex(columns=FEATURE_COLUMNS), ycol


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    default_csv = _find_default_csv(repo_root)
    ap = argparse.ArgumentParser(description="Train XGBoost + IsolationForest (AI4I tabular)")
    ap.add_argument("--csv", type=Path, default=default_csv, help="Chemin ai4i2020.csv")
    ap.add_argument(
        "--out",
        type=Path,
        default=repo_root / "modele_moteur_ia_inspect" / "models_tabular",
        help="Dossier de sortie des artefacts",
    )
    ap.add_argument("--test-size", type=float, default=0.2, help="Fraction test")
    args = ap.parse_args()

    if args.csv is None or not Path(args.csv).exists():
        print("Fichier CSV introuvable. Télécharge AI4I 2020 puis place ai4i2020.csv, ex.:", file=sys.stderr)
        print("  https://archive.ics.uci.edu/ml/machine-learning-databases/00601/ai4i2020.csv", file=sys.stderr)
        print("  ou sous iot-backend/ai4i2020.csv", file=sys.stderr)
        return 1

    df_raw = pd.read_csv(args.csv)
    X, y = _build_xy(df_raw)

    X_train, X_test, y_train, y_test = train_test_split(
        X.values, y, test_size=args.test_size, random_state=42, stratify=y
    )

    scaler = StandardScaler()
    X_train_s = scaler.fit_transform(X_train)
    X_test_s = scaler.transform(X_test)

    xgb = XGBClassifier(
        n_estimators=300,
        max_depth=5,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        reg_lambda=1.0,
        random_state=42,
        eval_metric="logloss",
    )
    xgb.fit(X_train_s, y_train)
    proba_test = xgb.predict_proba(X_test_s)[:, 1]
    try:
        auc = float(roc_auc_score(y_test, proba_test))
    except ValueError:
        auc = float("nan")
    try:
        ap = float(average_precision_score(y_test, proba_test))
    except ValueError:
        ap = float("nan")
    print(f"[train_tabular] ROC-AUC (test): {auc:.4f}  PR-AUC (test): {ap:.4f}")

    normal_mask = y_train == 0
    if normal_mask.sum() < 50:
        print("[train_tabular] Attention: peu d'échantillons normaux pour IsolationForest.", file=sys.stderr)
    iso = IsolationForest(
        n_estimators=200,
        contamination="auto",
        random_state=42,
        n_jobs=1,
    )
    iso.fit(X_train_s[normal_mask])

    train_normal_scores = iso.decision_function(X_train_s[normal_mask])
    # Anomalie si score en dessous du 5e percentile des normaux (ajustable)
    iso_threshold = float(np.quantile(train_normal_scores, 0.05))

    args.out.mkdir(parents=True, exist_ok=True)
    joblib.dump(scaler, args.out / "scaler_tabular.pkl")
    joblib.dump(xgb, args.out / "xgb_panne.pkl")
    joblib.dump(iso, args.out / "iso_forest.pkl")

    meta = {
        "version": "tabular-ai4i-v1",
        "feature_columns": FEATURE_COLUMNS,
        "iso_threshold": iso_threshold,
        "type_ord_map": TYPE_ORD,
        "source": "AI4I 2020",
        "metrics": {"roc_auc_test": auc, "pr_auc_test": ap},
        "csv_used": str(Path(args.csv).resolve()),
    }
    (args.out / "metadata_tabular.json").write_text(
        json.dumps(meta, indent=2), encoding="utf-8"
    )
    print(f"[train_tabular] Artefacts écrits dans: {args.out.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
