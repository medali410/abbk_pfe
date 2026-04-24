"""
Autoencoder for unsupervised anomaly detection.

Trained ONLY on NORMAL data.  At inference, high reconstruction error
signals an anomaly even for never-seen failure modes.
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
from sklearn.preprocessing import LabelEncoder, StandardScaler
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


def set_global_seed(seed: int = 42) -> None:
    os.environ["PYTHONHASHSEED"] = str(seed)
    random.seed(seed)
    np.random.seed(seed)
    tf.random.set_seed(seed)
    tf.keras.utils.set_random_seed(seed)


def save_json(data: dict, out_path: Path) -> None:
    out_path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def create_windows_flat(X: np.ndarray, window_size: int) -> np.ndarray:
    """Create sliding windows from a 2-D array (n_samples, n_features)."""
    windows = []
    for i in range(len(X) - window_size + 1):
        windows.append(X[i:i + window_size])
    return np.array(windows, dtype=np.float32)


def build_autoencoder(window_size: int, n_features: int) -> keras.Model:
    input_shape = (window_size, n_features)
    inp = keras.Input(shape=input_shape, name="ae_input")

    # Encoder
    x = layers.GRU(32, return_sequences=True)(inp)
    x = layers.GRU(16, return_sequences=False, name="bottleneck")(x)
    encoded = layers.Dense(8, activation="relu")(x)

    # Decoder
    x = layers.RepeatVector(window_size)(encoded)
    x = layers.GRU(16, return_sequences=True)(x)
    x = layers.GRU(32, return_sequences=True)(x)
    decoded = layers.TimeDistributed(layers.Dense(n_features), name="ae_output")(x)

    autoencoder = keras.Model(inp, decoded, name="anomaly_autoencoder")
    autoencoder.compile(optimizer=keras.optimizers.Adam(1e-3), loss="mse")
    return autoencoder


def main() -> None:
    parser = argparse.ArgumentParser(description="Train autoencoder for anomaly detection (NORMAL data only).")
    parser.add_argument("--data", required=True, help="Path to CSV dataset.")
    parser.add_argument("--out-dir", default="models_v3_lstm", help="Output directory (same as LSTM artifacts).")
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--window-size", type=int, default=WINDOW_SIZE)
    parser.add_argument("--percentile", type=float, default=97.0,
                        help="Percentile of NORMAL reconstruction error to set the anomaly threshold.")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(args.data)

    scaler_path = out_dir / "scaler.pkl"
    if scaler_path.exists():
        scaler = joblib.load(scaler_path)
        x_all = scaler.transform(df[CAPTEURS].astype(np.float32).values).astype(np.float32)
    else:
        scaler = StandardScaler()
        x_all = scaler.fit_transform(df[CAPTEURS].astype(np.float32).values).astype(np.float32)

    mask_normal = df["scenario"].str.upper() == "NORMAL"
    mask_failure = ~mask_normal
    x_normal = x_all[mask_normal.values]
    x_failure = x_all[mask_failure.values]

    print(f"NORMAL samples: {len(x_normal)}, FAILURE samples: {len(x_failure)}")

    ws = args.window_size
    win_normal = create_windows_flat(x_normal, ws)
    n_train = int(len(win_normal) * 0.85)
    win_train = win_normal[:n_train]
    win_val = win_normal[n_train:]

    print(f"Windows: train={len(win_train)}, val={len(win_val)}")

    ae = build_autoencoder(ws, len(CAPTEURS))
    ae.summary()

    callbacks = [
        keras.callbacks.EarlyStopping(monitor="val_loss", patience=10, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=4, min_lr=1e-6),
    ]

    history = ae.fit(
        win_train, win_train,
        validation_data=(win_val, win_val),
        epochs=args.epochs,
        batch_size=args.batch_size,
        callbacks=callbacks,
        verbose=1,
    )

    # Compute reconstruction error on NORMAL validation data to set threshold
    recon_val = ae.predict(win_val, verbose=0)
    mse_val = np.mean((win_val - recon_val) ** 2, axis=(1, 2))

    threshold = float(np.percentile(mse_val, args.percentile))
    mean_error = float(np.mean(mse_val))
    std_error = float(np.std(mse_val))

    print(f"\nNORMAL reconstruction error: mean={mean_error:.6f}, std={std_error:.6f}")
    print(f"Anomaly threshold (p{args.percentile}): {threshold:.6f}")

    # Test on failure data if available
    ae_metrics = {
        "threshold": threshold,
        "normal_mean_error": mean_error,
        "normal_std_error": std_error,
        "percentile_used": args.percentile,
    }

    if len(x_failure) >= ws:
        win_fail = create_windows_flat(x_failure, ws)
        recon_fail = ae.predict(win_fail, verbose=0)
        mse_fail = np.mean((win_fail - recon_fail) ** 2, axis=(1, 2))
        detected = float(np.mean(mse_fail > threshold))
        ae_metrics["failure_detection_rate"] = detected
        ae_metrics["failure_mean_error"] = float(np.mean(mse_fail))
        print(f"Failure detection rate: {detected * 100:.1f}%")

    ae.save(out_dir / "autoencoder.keras")
    save_json(ae_metrics, out_dir / "autoencoder_metrics.json")

    hist_serializable = {k: [float(v) for v in vals] for k, vals in history.history.items()}
    save_json({"history": hist_serializable}, out_dir / "autoencoder_history.json")

    print("\nAutoencoder training finished. Artifacts saved to:", out_dir.resolve())


if __name__ == "__main__":
    set_global_seed(42)
    main()
