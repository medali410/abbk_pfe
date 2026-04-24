"""
Generate realistic synthetic failure data for underrepresented scenarios.

Each scenario has a physics-inspired generative model that creates sensor
readings consistent with the failure mode:
  - SURCHAUFFE:       rising temperature, thermal runaway pattern
  - SURCHARGE:        high power draw, pressure spikes
  - USURE_GENERALE:   gradual degradation across all sensors
  - ROULEMENT:        high vibration, periodic ultrasonic spikes
  - ELECTRIQUE:       power fluctuation, magnetic anomalies
  - CAVITATION:       pressure drops + vibration spikes (hydraulic)
  - FUITE:            pressure loss pattern
  - DEGRADATION_HPC:  gradual temperature rise + power loss (turbofan)
  - PRESSION_HUILE:   oil pressure anomalies

Usage:
  python generate_synthetic_failures.py --base-data data/prepared/train_unified.csv \
      --out data/prepared/train_augmented.csv --samples-per-scenario 800
"""

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

CAPTEURS = [
    "temperature", "pression", "puissance", "vibration",
    "presence", "magnetique", "infrarouge",
]

MOTOR_TYPES = ["EL_S", "EL_M", "EL_L"]

SCENARIOS = {
    "SURCHAUFFE": {
        "temperature": (75, 110),
        "pression":    (0.02, 0.06),
        "puissance":   (70000, 130000),
        "vibration":   (1.5, 3.5),
        "presence":    (1, 1),
        "magnetique":  (0.3, 0.9),
        "infrarouge":  (320, 370),
    },
    "SURCHARGE": {
        "temperature": (60, 90),
        "pression":    (0.04, 0.12),
        "puissance":   (100000, 200000),
        "vibration":   (2.0, 5.0),
        "presence":    (1, 1),
        "magnetique":  (0.5, 0.95),
        "infrarouge":  (310, 350),
    },
    "USURE_GENERALE": {
        "temperature": (50, 80),
        "pression":    (0.03, 0.08),
        "puissance":   (40000, 80000),
        "vibration":   (2.5, 5.0),
        "presence":    (1, 1),
        "magnetique":  (0.2, 0.7),
        "infrarouge":  (305, 340),
    },
    "ROULEMENT": {
        "temperature": (55, 85),
        "pression":    (0.02, 0.05),
        "puissance":   (50000, 90000),
        "vibration":   (3.0, 8.0),
        "presence":    (1, 1),
        "magnetique":  (0.3, 0.8),
        "infrarouge":  (310, 345),
    },
    "ELECTRIQUE": {
        "temperature": (45, 95),
        "pression":    (0.01, 0.04),
        "puissance":   (20000, 150000),
        "vibration":   (1.0, 3.0),
        "presence":    (0, 1),
        "magnetique":  (0.05, 0.95),
        "infrarouge":  (300, 360),
    },
}


def generate_scenario(scenario: str, n: int, rng: np.random.RandomState) -> pd.DataFrame:
    """Generate n synthetic samples for a given failure scenario."""
    params = SCENARIOS.get(scenario, SCENARIOS["USURE_GENERALE"])
    rows = []
    for _ in range(n):
        motor_type = rng.choice(MOTOR_TYPES)
        severity = rng.uniform(0.3, 1.0)

        row = {}
        for cap in CAPTEURS:
            lo, hi = params[cap]
            base = lo + (hi - lo) * severity
            noise = rng.normal(0, (hi - lo) * 0.08)
            row[cap] = float(np.clip(base + noise, lo * 0.8, hi * 1.2))

        if scenario == "SURCHAUFFE":
            row["temperature"] += severity * rng.uniform(5, 20)
            row["infrarouge"] = row["temperature"] + rng.uniform(-5, 15)

        elif scenario == "ROULEMENT":
            row["vibration"] *= (1.0 + severity * rng.uniform(0.5, 1.5))

        elif scenario == "ELECTRIQUE":
            row["puissance"] *= rng.choice([0.3, 0.5, 1.5, 2.0])
            row["magnetique"] = rng.choice([0.05, 0.1, 0.85, 0.95])

        elif scenario == "SURCHARGE":
            row["puissance"] *= (1.0 + severity * 0.5)
            row["pression"] *= (1.0 + severity * 0.3)

        row["type_moteur"] = motor_type
        row["panne"] = 1
        row["anomalie"] = 1
        row["scenario"] = scenario
        row["rul"] = float(rng.uniform(0, 80) * (1 - severity))
        rows.append(row)

    return pd.DataFrame(rows)


def main():
    parser = argparse.ArgumentParser(description="Generate synthetic failure data.")
    parser.add_argument("--base-data", required=True, help="Path to original CSV dataset.")
    parser.add_argument("--out", required=True, help="Output augmented CSV path.")
    parser.add_argument("--samples-per-scenario", type=int, default=800,
                        help="Target number of TOTAL samples per failure scenario.")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    rng = np.random.RandomState(args.seed)

    df_orig = pd.read_csv(args.base_data)
    print(f"Original dataset: {len(df_orig)} rows")
    print("Original distribution:")
    print(df_orig["scenario"].value_counts().to_string())

    frames = [df_orig]
    target = args.samples_per_scenario

    for scenario in SCENARIOS:
        existing = len(df_orig[df_orig["scenario"] == scenario])
        needed = max(0, target - existing)
        if needed > 0:
            synth = generate_scenario(scenario, needed, rng)
            frames.append(synth)
            print(f"  {scenario}: generated {needed} synthetic samples (had {existing})")
        else:
            print(f"  {scenario}: already has {existing} >= {target}, skipping")

    df_aug = pd.concat(frames, ignore_index=True)
    df_aug = df_aug.sample(frac=1, random_state=rng).reset_index(drop=True)

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    df_aug.to_csv(args.out, index=False)

    print(f"\nAugmented dataset: {len(df_aug)} rows")
    print("New distribution:")
    print(df_aug["scenario"].value_counts().to_string())
    print(f"\nSaved to: {args.out}")


if __name__ == "__main__":
    main()
