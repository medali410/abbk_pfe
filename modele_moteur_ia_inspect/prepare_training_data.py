import argparse
from pathlib import Path

import numpy as np
import pandas as pd


def normalize_ai4i_columns(df: pd.DataFrame) -> pd.DataFrame:
    """
    Harmonise les en-têtes entre le CSV UCI officiel et certaines variantes Kaggle
    (ex. colonnes sans [K] / [rpm]).
    """
    df = df.copy()
    df.columns = [str(c).strip() for c in df.columns]

    aliases = {
        "Air temperature": "Air temperature [K]",
        "Process temperature": "Process temperature [K]",
        "Rotational speed": "Rotational speed [rpm]",
        "Torque": "Torque [Nm]",
        "Tool wear": "Tool wear [min]",
    }
    for short, full in aliases.items():
        if short in df.columns and full not in df.columns:
            df = df.rename(columns={short: full})

    # Scénario : dériver depuis les flags AI4I si pas de colonne Failure Type
    if "Failure Type" not in df.columns and "HDF" in df.columns:
        def _failure_type(r: pd.Series) -> str:
            if int(r.get("HDF", 0) or 0) == 1:
                return "Heat Dissipation Failure"
            if int(r.get("PWF", 0) or 0) == 1:
                return "Power Failure"
            if int(r.get("OSF", 0) or 0) == 1:
                return "Overstrain Failure"
            if int(r.get("TWF", 0) or 0) == 1:
                return "Tool Wear Failure"
            if int(r.get("RNF", 0) or 0) == 1:
                return "Random Failures"
            return "No Failure"

        df["Failure Type"] = df.apply(_failure_type, axis=1)

    return df


def map_scenario(row: pd.Series) -> str:
    ft = str(row.get("Failure Type", "No Failure")).strip().lower()
    if "heat" in ft:
        return "SURCHAUFFE"
    if "power" in ft:
        return "SURCHARGE"
    if "overstrain" in ft:
        return "USURE_GENERALE"
    if "tool wear" in ft:
        return "ROULEMENT"
    if "random" in ft:
        return "ELECTRIQUE"
    return "NORMAL"


def build_from_ai4i(df: pd.DataFrame) -> pd.DataFrame:
    # Map AI4I columns to expected training schema.
    out = pd.DataFrame()
    out["temperature"] = ((df["Air temperature [K]"] + df["Process temperature [K]"]) / 2.0).astype(float)
    out["pression"] = (df["Torque [Nm]"] / np.maximum(df["Rotational speed [rpm]"], 1)).astype(float)
    out["puissance"] = (df["Torque [Nm]"] * df["Rotational speed [rpm]"]).astype(float)
    out["vibration"] = (df["Rotational speed [rpm]"] / 1000.0).astype(float)
    out["presence"] = 1.0
    out["magnetique"] = df["Type"].map({"L": 0.3, "M": 0.6, "H": 0.9}).fillna(0.5).astype(float)
    out["infrarouge"] = df["Process temperature [K]"].astype(float)

    out["type_moteur"] = df["Type"].map({"L": "EL_S", "M": "EL_M", "H": "EL_L"}).fillna("EL_M")
    target_col = "Target" if "Target" in df.columns else "Machine failure"
    out["panne"] = df[target_col].astype(int)
    out["anomalie"] = df[target_col].astype(int)
    out["scenario"] = df.apply(map_scenario, axis=1)

    # Proxy RUL from tool wear (instantané AI4I). Pour une RUL en « heures réelles » jusqu’à panne,
    # il faudrait des séries temporelles avec timestamp de défaillance ; ce n’est pas dans ce CSV.
    wear = df["Tool wear [min]"].astype(float)
    max_wear = max(float(wear.max()), 1.0)
    out["rul"] = (max_wear - wear).clip(lower=0.0)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare unified training dataset for improved model.")
    parser.add_argument("--ai4i", nargs="+", required=True, help="List of AI4I-style CSV files.")
    parser.add_argument("--out", required=True, help="Output CSV path.")
    args = parser.parse_args()

    frames = []
    for csv_path in args.ai4i:
        p = Path(csv_path)
        df = pd.read_csv(p)
        df = normalize_ai4i_columns(df)
        frames.append(build_from_ai4i(df))

    data = pd.concat(frames, ignore_index=True).drop_duplicates()
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    data.to_csv(args.out, index=False)
    print(f"Saved prepared dataset: {args.out}")
    print(f"Shape: {data.shape}")
    print("Scenarios:", data["scenario"].value_counts().to_dict())


if __name__ == "__main__":
    main()
