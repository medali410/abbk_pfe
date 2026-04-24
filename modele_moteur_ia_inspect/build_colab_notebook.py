"""
Génère Colab_entrainement_AI4I.ipynb — entraînement 100 % dans Colab SANS Google Drive.

Lance sur ton PC :  python build_colab_notebook.py
Puis importe le .ipynb dans Google Colab et exécute les cellules dans l'ordre.
"""
import base64
import json
from pathlib import Path


def cell_md(text: str) -> dict:
    return {"cell_type": "markdown", "metadata": {}, "source": [ln + "\n" for ln in text.split("\n")]}


def cell_code(text: str) -> dict:
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": [ln + "\n" for ln in text.split("\n")],
    }


def main() -> None:
    root = Path(__file__).resolve().parent
    prepare_src = (root / "prepare_training_data.py").read_text(encoding="utf-8")
    train_src = (root / "train_improved_model.py").read_text(encoding="utf-8")

    prep_b64 = base64.b64encode(prepare_src.encode("utf-8")).decode("ascii")
    train_b64 = base64.b64encode(train_src.encode("utf-8")).decode("ascii")

    cells = []

    cells.append(
        cell_md(
            """# DALI — Entraînement **100 % Google Colab** (sans Drive)

Ce notebook **ne nécessite pas** Google Drive : les fichiers `prepare_training_data.py` et `train_improved_model.py` ont été **embarqués** dans le notebook au moment de sa génération sur ton PC.

### Sur ton PC (une fois)
Dans le dossier `modele_moteur_ia_inspect` :
```bash
python build_colab_notebook.py
```

### Sur Colab
1. **Fichier → Importer une note** → choisir `Colab_entrainement_AI4I.ipynb`.
2. **Exécution → Tout exécuter** (ou cellule par cellule, de haut en bas).
3. À la fin : téléchargement du **ZIP** des modèles (`best_model_v3.keras`, `scaler.pkl`, `metadata.json`, …).

### GPU (recommandé)
**Exécution → Modifier le type d’exécution → T4 GPU** (accélère TensorFlow).

### Données
Le CSV **AI4I 2020** est téléchargé depuis **UCI** (équivalent au jeu Kaggle)."""
        )
    )

    cells.append(cell_md("## 1) Dépendances"))
    cells.append(cell_code("%pip install -q tensorflow pandas scikit-learn matplotlib joblib"))

    cells.append(cell_md("## 2) Télécharger le dataset AI4I (UCI)"))
    cells.append(
        cell_code(
            """import urllib.request
from pathlib import Path

Path("/content/data").mkdir(parents=True, exist_ok=True)
RAW = "/content/data/ai4i2020.csv"
url = "https://archive.ics.uci.edu/ml/machine-learning-databases/00601/ai4i2020.csv"
print("Téléchargement...", url)
urllib.request.urlretrieve(url, RAW)

import pandas as pd
df = pd.read_csv(RAW)
print("Shape:", df.shape)
print(df.head(2))"""
        )
    )

    cells.append(
        cell_md(
            """## 3) Écrire les scripts du projet (embarqués)

Les deux `.py` sont recréés sous `/content/scripts/` à partir du notebook."""
        )
    )

    # Une seule ligne base64 par fichier évite les problèmes de guillemets dans le source Python
    write_cell = f"""import base64
from pathlib import Path

Path("/content/scripts").mkdir(parents=True, exist_ok=True)

prep_b64 = "{prep_b64}"
train_b64 = "{train_b64}"

open("/content/scripts/prepare_training_data.py", "wb").write(base64.b64decode(prep_b64))
open("/content/scripts/train_improved_model.py", "wb").write(base64.b64decode(train_b64))
print("OK : /content/scripts/prepare_training_data.py")
print("OK : /content/scripts/train_improved_model.py")"""

    cells.append(cell_code(write_cell))

    cells.append(cell_md("## 4) Préparer le CSV d’entraînement"))
    cells.append(
        cell_code(
            """import os
from pathlib import Path

Path("/content/dali_out").mkdir(parents=True, exist_ok=True)
os.chdir("/content/scripts")
!python prepare_training_data.py --ai4i /content/data/ai4i2020.csv --out /content/dali_out/train_prepared.csv"""
        )
    )

    cells.append(cell_md("## 5) Entraîner le modèle LSTM (réduire `--epochs` pour un test rapide)"))
    cells.append(
        cell_code(
            """import os
os.chdir("/content/scripts")
!python train_improved_model.py --data /content/dali_out/train_prepared.csv --out-dir /content/dali_out/models_colab --epochs 45 --batch-size 128"""
        )
    )

    cells.append(
        cell_md(
            """## 6) Télécharger les artefacts sur ton PC

Dézippe le fichier puis copie le dossier vers `modele_moteur_ia_inspect/models_v3_lstm` ou configure `MODEL_ARTIFACTS_DIR` pour `inference_api`."""
        )
    )

    cells.append(
        cell_code(
            """!ls -la /content/dali_out/models_colab
!zip -r /content/dali_models_colab.zip /content/dali_out/models_colab
from google.colab import files
files.download("/content/dali_models_colab.zip")"""
        )
    )

    cells.append(
        cell_md(
            """---

### Optionnel : Google Drive

Si tu préfères garder les `.py` sur Drive au lieu du notebook embarqué, utilise une ancienne version du notebook ou monte Drive et lance les mêmes commandes `python` depuis ton dossier Drive."""
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

    out = root / "Colab_entrainement_AI4I.ipynb"
    out.write_text(json.dumps(nb, indent=1, ensure_ascii=False), encoding="utf-8")
    print("OK:", out)
    print("Taille notebook (~Ko):", out.stat().st_size // 1024)


if __name__ == "__main__":
    main()
