import requests, json

BASE = "http://localhost:8001"

def test(name, payload):
    r = requests.post(f"{BASE}/predict", json=payload)
    print(f"\n{'='*50}")
    print(f"TEST : {name}")
    print(json.dumps(r.json(), indent=2, ensure_ascii=True))

# Machine normale
test("NORMAL", {
    "machine_id": "MAC_VERIN_001",
    "temperature_contact": 35.0,
    "temperature_infrarouge": 37.0,
    "vibration_x": 0.05, "vibration_y": 0.04,
    "courant": 2.1, "puissance": 450.0,
    "machine_type": "M"
})

# Surchauffe
test("SURCHAUFFE", {
    "machine_id": "MAC_VERIN_002",
    "temperature_contact": 88.0,
    "temperature_infrarouge": 93.0,
    "vibration_x": 0.3, "vibration_y": 0.2,
    "courant": 5.0, "puissance": 1100.0,
    "machine_type": "M"
})

# Surcharge
test("SURCHARGE", {
    "machine_id": "MAC_PRESSE_003",
    "temperature_contact": 55.0,
    "temperature_infrarouge": 58.0,
    "vibration_x": 0.4, "vibration_y": 0.3,
    "courant": 18.0, "puissance": 5800.0,
    "machine_type": "H"
})

# Roulement
test("ROULEMENT", {
    "machine_id": "MAC_MOTEUR_004",
    "temperature_contact": 50.0,
    "temperature_infrarouge": 52.0,
    "vibration_x": 2.8, "vibration_y": 2.5,
    "courant": 4.0, "puissance": 900.0,
    "machine_type": "L"
})
