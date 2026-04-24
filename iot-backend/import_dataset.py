#!/usr/bin/env python3
# ============================================================
#  ABBKA - Import Dataset dans MongoDB
# ============================================================

import pandas as pd
from pymongo import MongoClient
from datetime import datetime
import numpy as np

# ==================== CONFIGURATION ====================
MONGO_URI = "mongodb://localhost:27017/"
DATABASE_NAME = "abbka"
COLLECTION_NAME = "training_data"

# ==================== CONNEXION MONGODB ====================
client = MongoClient(MONGO_URI)
db = client[DATABASE_NAME]
collection = db[COLLECTION_NAME]

print("╔════════════════════════════════════════════════════════╗")
print("║       ABBKA - Import Dataset Training                 ║")
print("╚════════════════════════════════════════════════════════╝\n")

# ==================== CHARGER DATASET ====================

print("[1/4] Chargement du fichier CSV...")
df = pd.read_csv('ai4i2020.csv')
print(f"  ✅ {len(df)} lignes chargées\n")

print("[2/4] Aperçu des données :")
print(df.head())
print(f"\nColonnes : {list(df.columns)}\n")

# ==================== NETTOYER DONNÉES ====================
print("[3/4] Nettoyage des données...")
collection.delete_many({})
print(f"  🗑️  Collection vidée")

# ==================== TRANSFORMATION ====================
print("\n[4/4] Insertion dans MongoDB...")

records = []
for idx, row in df.iterrows():
    record = {
        "udi": int(row.get('UDI', idx)),
        "product_id": row.get('Product ID', f'PROD_{idx}'),
        "type": row.get('Type', 'M'),
        "metrics": {
            "thermal": round(float(row.get('Air temperature [K]', 300)) - 273.15, 1),
            "process_temp": round(float(row.get('Process temperature [K]', 310)) - 273.15, 1),
            "rotational_speed": int(row.get('Rotational speed [rpm]', 1500)),
            "torque": round(float(row.get('Torque [Nm]', 40)), 2),
            "tool_wear": int(row.get('Tool wear [min]', 0)),
            "pressure": round(float(row.get('Torque [Nm]', 40)) / 10.0, 2),
            "power": round(float(row.get('Rotational speed [rpm]', 1500)) / 20.0, 1),
        },
        "failure": {
            "machine_failure": int(row.get('Machine failure', 0)),
            "twf": int(row.get('TWF', 0)),
            "hdf": int(row.get('HDF', 0)),
            "pwf": int(row.get('PWF', 0)),
            "osf": int(row.get('OSF', 0)),
            "rnf": int(row.get('RNF', 0))
        },
        "timestamp": datetime.utcnow(),
        "source": "AI4I_2020_Dataset",
        "imported_at": datetime.utcnow()
    }
    records.append(record)

    if len(records) >= 1000:
        collection.insert_many(records)
        print(f"  📥 {idx+1} enregistrements insérés...")
        records = []

if records:
    collection.insert_many(records)
    print(f"  📥 {len(records)} enregistrements finaux insérés...")

# ==================== VÉRIFICATION ====================
total_count = collection.count_documents({})
failure_count = collection.count_documents({"failure.machine_failure": 1})

print(f"\n╔════════════════════════════════════════════════════════╗")
print(f"║  ✅ IMPORT TERMINÉ                                     ║")
print(f"║  📊 Total enregistrements : {total_count:<8}                  ║")
print(f"║  ⚠️  Pannes détectées     : {failure_count:<8} ({failure_count/total_count*100:.1f}%)           ║")
print(f"╚════════════════════════════════════════════════════════╝")

# ==================== CRÉER INDEXES ====================
print("\n[INDEX] Création des index MongoDB...")
collection.create_index("udi")
collection.create_index("timestamp")
collection.create_index("failure.machine_failure")
print("  ✅ Index créés\n")

# ==================== STATISTIQUES ====================
print("[STATS] Statistiques du dataset :")
pipeline = [
    {
        "$group": {
            "_id": "$type",
            "count": {"$sum": 1},
            "avg_temp": {"$avg": "$metrics.thermal"},
            "failure_rate": {"$avg": "$failure.machine_failure"}
        }
    }
]
stats = list(collection.aggregate(pipeline))
for stat in stats:
    print(f"  Type {stat['_id']} : {stat['count']} samples, "
          f"Temp moy: {stat['avg_temp']:.1f}°C, "
          f"Taux panne: {stat['failure_rate']*100:.1f}%")

print("\n✅ Prêt pour l'entraînement IA !\n")
