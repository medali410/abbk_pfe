"""Génère Colab_CODE_COMPLET.ipynb : toutes les cellules + %%writefile des 2 scripts sources."""
import json
from pathlib import Path


def cell_md(text: str) -> dict:
    return {"cell_type": "markdown", "metadata": {}, "source": [ln + "\n" for ln in text.split("\n")]}


def cell_code_from_lines(lines: list[str]) -> dict:
    src = [ln if ln.endswith("\n") else ln + "\n" for ln in lines]
    if src and not src[-1].endswith("\n"):
        src[-1] += "\n"
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": src,
    }


def cell_code(text: str) -> dict:
    return cell_code_from_lines(text.split("\n"))


def writefile_cell(dest: str, file_content: str) -> dict:
    body = file_content.replace("\r\n", "\n")
    lines = [f"%%writefile {dest}\n"] + body.splitlines(keepends=True)
    if lines[-1] and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    return cell_code_from_lines(lines)


def main() -> None:
    root = Path(__file__).resolve().parent
    prep = (root / "prepare_training_data.py").read_text(encoding="utf-8")
    train = (root / "train_improved_model.py").read_text(encoding="utf-8")

    cells = []

    cells.append(
        cell_md(
            """# Code Colab COMPLET — entraînement modèle IA DALI

Ce notebook contient **tout le code** : les deux scripts Python sont recréés avec `%%writefile`, puis exécutés.

**Ordre** : exécute les cellules **une par une** de haut en bas (ou *Exécution → Tout exécuter*).

**GPU** : *Exécution → Modifier le type d’exécution → T4 GPU* (recommandé)."""
        )
    )

    cells.append(cell_md("## Cellule 1 — Dépendances"))
    cells.append(cell_code("%pip install -q tensorflow pandas scikit-learn matplotlib joblib"))

    cells.append(cell_md("## Cellule 2 — Télécharger AI4I 2020 (UCI)"))
    cells.append(
        cell_code(
            """import urllib.request
from pathlib import Path

Path("/content/data").mkdir(parents=True, exist_ok=True)
RAW = "/content/data/ai4i2020.csv"
url = "https://archive.ics.uci.edu/ml/machine-learning-databases/00601/ai4i2020.csv"
urllib.request.urlretrieve(url, RAW)

import pandas as pd
print(pd.read_csv(RAW, nrows=2))"""
        )
    )

    cells.append(cell_md("## Cellule 3 — Dossier des scripts"))
    cells.append(
        cell_code(
            """from pathlib import Path
Path("/content/scripts").mkdir(parents=True, exist_ok=True)"""
        )
    )

    cells.append(
        cell_md(
            """## Cellule 4 — Créer `prepare_training_data.py`

La cellule suivante est **longue** : c’est normal (fichier complet)."""
        )
    )
    cells.append(writefile_cell("/content/scripts/prepare_training_data.py", prep))

    cells.append(cell_md("## Cellule 5 — Créer `train_improved_model.py`"))
    cells.append(writefile_cell("/content/scripts/train_improved_model.py", train))

    cells.append(cell_md("## Cellule 6 — Préparer le CSV"))
    cells.append(
        cell_code(
            """import os
from pathlib import Path
Path("/content/scripts").mkdir(parents=True, exist_ok=True)
Path("/content/dali_out").mkdir(parents=True, exist_ok=True)
os.chdir("/content/scripts")
!python prepare_training_data.py --ai4i /content/data/ai4i2020.csv --out /content/dali_out/train_prepared.csv"""
        )
    )

    cells.append(cell_md("## Cellule 7 — Entraîner le LSTM"))
    cells.append(
        cell_code(
            """import os
os.chdir("/content/scripts")
!python train_improved_model.py --data /content/dali_out/train_prepared.csv --out-dir /content/dali_out/models_colab --epochs 45 --batch-size 128"""
        )
    )

    cells.append(cell_md("## Cellule 8 — Télécharger le ZIP sur ton PC"))
    cells.append(
        cell_code(
            """!ls -la /content/dali_out/models_colab
!zip -r /content/dali_models_colab.zip /content/dali_out/models_colab
from google.colab import files
files.download("/content/dali_models_colab.zip")"""
        )
    )

    nb = {
        "nbformat": 4,
        "nbformat_minor": 5,
        "metadata": {
            "kernelspec": {
                "display_name": "Python 3",
                "language": "python",
                "name": "python3",
            },
            "language_info": {"name": "python"},
        },
        "cells": cells,
    }

    out = root / "Colab_CODE_COMPLET.ipynb"
    out.write_text(json.dumps(nb, indent=1, ensure_ascii=False), encoding="utf-8")
    print("OK:", out, "Ko:", out.stat().st_size // 1024)


if __name__ == "__main__":
    main()
