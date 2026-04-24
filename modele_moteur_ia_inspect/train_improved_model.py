"""
Improved predictive maintenance training pipeline.

Features:
  - SMOTE oversampling for minority failure scenarios
  - Focal Loss for imbalanced binary/multiclass outputs
  - Sliding-window transformation for temporal patterns (LSTM/GRU)
  - Multi-output: panne, rul, anomalie, scenario
"""

import argparse
import json
import os
import random
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    mean_absolute_error,
    mean_squared_error,
    precision_score,
    recall_score,
)
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.utils.class_weight import compute_class_weight
from tensorflow import keras
from tensorflow.keras import layers

CAPTEURS = [
    "temperature",
    "pression",
    "puissance",
    "vibration",
    "presence",
    "magnetique",
    "infrarouge",
]

WINDOW_SIZE = 10


# ---------------------------------------------------------------------------
# Focal Loss  (handles class imbalance much better than cross-entropy)
# ---------------------------------------------------------------------------

def binary_focal_loss(gamma=2.0, alpha=0.75):
    """Focal loss factory for binary classification (panne / anomalie)."""
    def loss_fn(y_true, y_pred):
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1.0 - 1e-7)
        y_true = tf.cast(y_true, tf.float32)
        bce = -y_true * tf.math.log(y_pred) - (1 - y_true) * tf.math.log(1 - y_pred)
        p_t = y_true * y_pred + (1 - y_true) * (1 - y_pred)
        alpha_t = y_true * alpha + (1 - y_true) * (1 - alpha)
        focal_weight = alpha_t * tf.pow(1.0 - p_t, gamma)
        return tf.reduce_mean(focal_weight * bce)
    return loss_fn


def sparse_categorical_focal_loss(gamma=2.0):
    """Focal loss factory for sparse multiclass (scenario)."""
    def loss_fn(y_true, y_pred):
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1.0 - 1e-7)
        y_true = tf.cast(tf.reshape(y_true, [-1]), tf.int32)
        n_classes = tf.shape(y_pred)[1]
        one_hot = tf.one_hot(y_true, n_classes)
        ce = -one_hot * tf.math.log(y_pred)
        p_t = tf.reduce_sum(one_hot * y_pred, axis=-1, keepdims=True)
        focal_weight = tf.pow(1.0 - p_t, gamma)
        return tf.reduce_mean(focal_weight * ce)
    return loss_fn


# ---------------------------------------------------------------------------
# SMOTE-like oversampling (pure numpy, avoids imblearn dependency)
# ---------------------------------------------------------------------------

def smote_oversample(X: np.ndarray, y: np.ndarray, target_per_class: int | None = None,
                     k: int = 5, seed: int = 42) -> tuple[np.ndarray, np.ndarray]:
    """Simple SMOTE for 2-D feature arrays. Returns oversampled X, y."""
    rng = np.random.RandomState(seed)
    classes, counts = np.unique(y, return_counts=True)
    if target_per_class is None:
        target_per_class = int(counts.max())

    X_parts, y_parts = [X], [y]
    for cls, cnt in zip(classes, counts):
        if cnt >= target_per_class:
            continue
        idx_cls = np.where(y == cls)[0]
        n_needed = target_per_class - cnt
        k_actual = min(k, cnt - 1) if cnt > 1 else 0
        if k_actual == 0:
            chosen = rng.choice(idx_cls, size=n_needed, replace=True)
            noise = rng.normal(0, 0.02, size=(n_needed, X.shape[1])).astype(X.dtype)
            X_parts.append(X[chosen] + noise)
            y_parts.append(np.full(n_needed, cls, dtype=y.dtype))
            continue
        from sklearn.neighbors import NearestNeighbors
        nn = NearestNeighbors(n_neighbors=k_actual + 1).fit(X[idx_cls])
        neighbors = nn.kneighbors(X[idx_cls], return_distance=False)[:, 1:]
        synth_X = []
        for _ in range(n_needed):
            i = rng.randint(0, cnt)
            j = neighbors[i, rng.randint(0, k_actual)]
            lam = rng.uniform(0, 1)
            synth_X.append(X[idx_cls[i]] + lam * (X[idx_cls[j]] - X[idx_cls[i]]))
        X_parts.append(np.array(synth_X, dtype=X.dtype))
        y_parts.append(np.full(n_needed, cls, dtype=y.dtype))

    return np.concatenate(X_parts, axis=0), np.concatenate(y_parts, axis=0)


# ---------------------------------------------------------------------------
# Sliding window transformation
# ---------------------------------------------------------------------------

def create_windows(X_capteurs: np.ndarray, X_type: np.ndarray,
                   y_panne: np.ndarray, y_rul: np.ndarray,
                   y_anomalie: np.ndarray, y_scenario: np.ndarray,
                   window_size: int = WINDOW_SIZE):
    """
    Build sliding windows grouped by motor-type sequences.
    For training data that is not truly sequential, we simulate sequences
    by sorting within each motor type then sliding a window.
    """
    n_samples, n_features = X_capteurs.shape
    if n_samples < window_size:
        X_capteurs = np.tile(X_capteurs, (window_size, 1))[:window_size * n_samples]
        raise ValueError(f"Not enough samples ({n_samples}) for window_size={window_size}")

    windows, w_types = [], []
    wp, wr, wa, ws = [], [], [], []

    unique_types = np.unique(X_type)
    for t in unique_types:
        mask = X_type == t
        Xt = X_capteurs[mask]
        yt_panne = y_panne[mask]
        yt_rul = y_rul[mask]
        yt_anom = y_anomalie[mask]
        yt_scen = y_scenario[mask]

        for i in range(len(Xt) - window_size + 1):
            windows.append(Xt[i:i + window_size])
            w_types.append(t)
            wp.append(yt_panne[i + window_size - 1])
            wr.append(yt_rul[i + window_size - 1])
            wa.append(yt_anom[i + window_size - 1])
            ws.append(yt_scen[i + window_size - 1])

    return (
        np.array(windows, dtype=np.float32),
        np.array(w_types, dtype=np.int32),
        np.array(wp, dtype=np.float32),
        np.array(wr, dtype=np.float32),
        np.array(wa, dtype=np.float32),
        np.array(ws, dtype=np.int32),
    )


# ---------------------------------------------------------------------------
# LSTM model
# ---------------------------------------------------------------------------

def build_lstm_model(n_types: int, n_scenarios: int,
                     window_size: int = WINDOW_SIZE,
                     n_features: int = len(CAPTEURS)) -> keras.Model:
    input_seq = keras.Input(shape=(window_size, n_features), name="capteurs_seq")
    input_type = keras.Input(shape=(1,), name="type_moteur")

    embed = layers.Embedding(input_dim=n_types, output_dim=8, name="type_embedding")(input_type)
    embed = layers.Flatten()(embed)
    embed_repeated = layers.RepeatVector(window_size)(embed)

    x = layers.Concatenate(axis=-1)([input_seq, embed_repeated])

    x = layers.Bidirectional(layers.GRU(64, return_sequences=True))(x)
    x = layers.Dropout(0.3)(x)
    x = layers.Bidirectional(layers.GRU(32, return_sequences=False))(x)
    x = layers.BatchNormalization()(x)
    x = layers.Dropout(0.3)(x)

    shared = layers.Dense(64, activation="relu")(x)
    shared = layers.BatchNormalization()(shared)
    shared = layers.Dropout(0.2)(shared)
    shared = layers.Dense(32, activation="relu")(shared)

    out_panne = layers.Dense(1, activation="sigmoid", name="panne")(shared)
    out_rul = layers.Dense(1, activation="sigmoid", name="rul")(shared)
    out_anomalie = layers.Dense(1, activation="sigmoid", name="anomalie")(shared)
    out_scenario = layers.Dense(n_scenarios, activation="softmax", name="scenario")(shared)

    model = keras.Model(
        inputs=[input_seq, input_type],
        outputs=[out_panne, out_rul, out_anomalie, out_scenario],
    )
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=1e-3),
        loss={
            "panne": binary_focal_loss(gamma=2.0, alpha=0.75),
            "rul": "mse",
            "anomalie": binary_focal_loss(gamma=2.0, alpha=0.75),
            "scenario": sparse_categorical_focal_loss(gamma=2.0),
        },
        metrics={
            "panne": ["accuracy"],
            "rul": ["mae"],
            "anomalie": ["accuracy"],
            "scenario": ["accuracy"],
        },
    )
    return model


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def save_json(data: dict, out_path: Path) -> None:
    out_path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def set_global_seed(seed: int = 42) -> None:
    os.environ["PYTHONHASHSEED"] = str(seed)
    random.seed(seed)
    np.random.seed(seed)
    tf.random.set_seed(seed)
    tf.keras.utils.set_random_seed(seed)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Train LSTM predictive maintenance model with SMOTE + Focal Loss.")
    parser.add_argument("--data", required=True, help="Path to CSV dataset.")
    parser.add_argument("--out-dir", default="models_v3_lstm", help="Output directory.")
    parser.add_argument("--epochs", type=int, default=80)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--window-size", type=int, default=WINDOW_SIZE)
    parser.add_argument("--smote-target", type=int, default=None,
                        help="Target samples per scenario class (default: match majority).")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # ---- Load data ----
    df = pd.read_csv(args.data)
    required = CAPTEURS + ["type_moteur", "panne", "rul", "anomalie", "scenario"]
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(f"Missing columns: {missing}")

    le_type = LabelEncoder()
    le_scenario = LabelEncoder()

    x_capteurs = df[CAPTEURS].astype(np.float32).values
    x_type = le_type.fit_transform(df["type_moteur"]).astype(np.int32)
    y_panne = df["panne"].astype(np.float32).values
    y_rul_raw = df["rul"].astype(np.float32).values
    y_anomalie = df["anomalie"].astype(np.float32).values
    y_scenario = le_scenario.fit_transform(df["scenario"]).astype(np.int32)

    rul_max = float(np.max(y_rul_raw)) if np.max(y_rul_raw) > 0 else 1.0
    y_rul = y_rul_raw / rul_max

    scaler = StandardScaler()
    x_capteurs = scaler.fit_transform(x_capteurs).astype(np.float32)

    print(f"Dataset: {len(df)} rows, {len(le_type.classes_)} motor types, {len(le_scenario.classes_)} scenarios")
    print("Scenario distribution BEFORE SMOTE:", dict(zip(*np.unique(y_scenario, return_counts=True))))

    # ---- SMOTE on the flat data (before windowing) ----
    flat_features = np.hstack([x_capteurs, x_type.reshape(-1, 1).astype(np.float32)])
    flat_labels = y_scenario

    smote_target = args.smote_target
    if smote_target is None:
        _, counts = np.unique(flat_labels, return_counts=True)
        smote_target = min(int(counts.max()), max(int(counts.max() * 0.3), 500))

    flat_features_os, y_scenario_os = smote_oversample(flat_features, flat_labels,
                                                        target_per_class=smote_target)

    x_capteurs_os = flat_features_os[:, :-1]
    x_type_os = flat_features_os[:, -1].astype(np.int32)

    n_orig = len(y_panne)
    n_new = len(y_scenario_os) - n_orig
    y_panne_os = np.concatenate([y_panne, np.ones(n_new, dtype=np.float32)])
    y_anomalie_os = np.concatenate([y_anomalie, np.ones(n_new, dtype=np.float32)])
    y_rul_os = np.concatenate([y_rul, np.full(n_new, 0.1, dtype=np.float32)])

    print(f"After SMOTE: {len(y_scenario_os)} rows")
    print("Scenario distribution AFTER SMOTE:", dict(zip(*np.unique(y_scenario_os, return_counts=True))))

    # ---- Split before windowing (avoid leakage) ----
    idx = np.arange(len(y_scenario_os))
    idx_train, idx_test = train_test_split(idx, test_size=0.2, random_state=42, stratify=y_scenario_os)

    # ---- Create windows ----
    ws = args.window_size
    win_train = create_windows(
        x_capteurs_os[idx_train], x_type_os[idx_train],
        y_panne_os[idx_train], y_rul_os[idx_train],
        y_anomalie_os[idx_train], y_scenario_os[idx_train],
        window_size=ws,
    )
    win_test = create_windows(
        x_capteurs_os[idx_test], x_type_os[idx_test],
        y_panne_os[idx_test], y_rul_os[idx_test],
        y_anomalie_os[idx_test], y_scenario_os[idx_test],
        window_size=ws,
    )

    xw_train, xt_train, yp_train, yr_train, ya_train, ys_train = win_train
    xw_test, xt_test, yp_test, yr_test, ya_test, ys_test = win_test

    print(f"Windows: train={len(xw_train)}, test={len(xw_test)} (window_size={ws})")

    # ---- Build & train LSTM ----
    model = build_lstm_model(
        n_types=len(le_type.classes_),
        n_scenarios=len(le_scenario.classes_),
        window_size=ws,
        n_features=len(CAPTEURS),
    )
    model.summary()

    callbacks = [
        keras.callbacks.EarlyStopping(monitor="val_loss", patience=12, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=5, min_lr=1e-6),
    ]

    # Use tf.data.Dataset to avoid Keras 3 multi-output sample_weight bugs
    n_val = int(len(xw_train) * 0.15)
    idx_shuf = np.random.permutation(len(xw_train))
    val_idx, trn_idx = idx_shuf[:n_val], idx_shuf[n_val:]

    ds_train = tf.data.Dataset.from_tensor_slices((
        {"capteurs_seq": xw_train[trn_idx], "type_moteur": xt_train[trn_idx]},
        {"panne": yp_train[trn_idx], "rul": yr_train[trn_idx],
         "anomalie": ya_train[trn_idx], "scenario": ys_train[trn_idx]},
    )).shuffle(8192).batch(args.batch_size).prefetch(tf.data.AUTOTUNE)

    ds_val = tf.data.Dataset.from_tensor_slices((
        {"capteurs_seq": xw_train[val_idx], "type_moteur": xt_train[val_idx]},
        {"panne": yp_train[val_idx], "rul": yr_train[val_idx],
         "anomalie": ya_train[val_idx], "scenario": ys_train[val_idx]},
    )).batch(args.batch_size).prefetch(tf.data.AUTOTUNE)

    history = model.fit(
        ds_train,
        validation_data=ds_val,
        epochs=args.epochs,
        callbacks=callbacks,
        verbose=1,
    )

    # ---- Evaluate ----
    pred_panne, pred_rul, pred_anomalie, pred_scenario = model.predict(
        {"capteurs_seq": xw_test, "type_moteur": xt_test}, verbose=0
    )

    y_hat_panne = (pred_panne.reshape(-1) >= 0.5).astype(int)
    y_hat_anomalie = (pred_anomalie.reshape(-1) >= 0.5).astype(int)
    y_hat_rul = pred_rul.reshape(-1) * rul_max
    y_hat_scenario = np.argmax(pred_scenario, axis=1)

    metrics = {
        "panne_accuracy": float(accuracy_score(yp_test, y_hat_panne)),
        "anomalie_accuracy": float(accuracy_score(ya_test, y_hat_anomalie)),
        "rul_mae": float(mean_absolute_error(yr_test * rul_max, y_hat_rul)),
        "rul_rmse": float(np.sqrt(mean_squared_error(yr_test * rul_max, y_hat_rul))),
        "scenario_accuracy": float(accuracy_score(ys_test, y_hat_scenario)),
        "scenario_precision_macro": float(precision_score(ys_test, y_hat_scenario, average="macro", zero_division=0)),
        "scenario_recall_macro": float(recall_score(ys_test, y_hat_scenario, average="macro", zero_division=0)),
        "scenario_f1_macro": float(f1_score(ys_test, y_hat_scenario, average="macro", zero_division=0)),
    }

    report = classification_report(
        ys_test, y_hat_scenario,
        target_names=list(le_scenario.classes_),
        zero_division=0, output_dict=True,
    )
    cm = confusion_matrix(ys_test, y_hat_scenario).tolist()

    # ---- Save artifacts ----
    model.save(out_dir / "best_model_v3.keras")
    joblib.dump(scaler, out_dir / "scaler.pkl")
    joblib.dump(le_type, out_dir / "le_type.pkl")
    joblib.dump(le_scenario, out_dir / "le_scenario.pkl")

    save_json(metrics, out_dir / "metrics.json")
    hist_serializable = {k: [float(v) for v in vals] for k, vals in history.history.items()}
    save_json({"history": hist_serializable}, out_dir / "training_history.json")
    save_json({"classification_report": report, "confusion_matrix": cm}, out_dir / "scenario_diagnostics.json")
    save_json(
        {
            "version": "3.0-lstm",
            "n_types": int(len(le_type.classes_)),
            "n_scenarios": int(len(le_scenario.classes_)),
            "types_moteurs": list(le_type.classes_),
            "scenarios": list(le_scenario.classes_),
            "capteurs": CAPTEURS,
            "rul_max": rul_max,
            "window_size": ws,
            "model_type": "lstm",
            "smote_target_per_class": smote_target,
        },
        out_dir / "metadata.json",
    )

    # Export TFLite for edge deployment
    try:
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        tflite_model = converter.convert()
        (out_dir / "model_v3.tflite").write_bytes(tflite_model)
        print("TFLite model exported.")
    except Exception as e:
        print(f"TFLite export skipped: {e}")

    print("\nTraining finished. Artifacts saved to:", out_dir.resolve())
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    set_global_seed(42)
    main()
