import re
import os

path = r'C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\ai_analysis_page.dart'
with open(path, 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Emojis and corrupted strings
replacements = {
    'Ã°Å¸â€ Â´ Mode DANGER': '🔴 Mode DANGER',
    'Ã°Å¸Å¸Â  Mode RISQUE': '🟠 Mode RISQUE',
    'Ã°Å¸Å¸Â¢ Mode NORMAL': '🟢 Mode NORMAL',
    'Ã‚Â°C': '°C',
    'Ã°Å¸Å¸Â¢': '🟢',
    'Ã°Å¸Å¸Â ': '🟠',
    'Ã°Å¸â€ Â´': '🔴',
    'MAGNÃ‰TIQUE': 'MAGNÉTIQUE',
    'MÃ©canique': 'Mécanique',
    'ArrÃªt': 'Arrêt',
    'immÃ©diat': 'immédiat',
    'recommandÃ©': 'recommandé',
    'renforcÃ©e': 'renforcée',
    'ArrÃƒÂªt': 'Arrêt',
    'immÃƒÂ©diat': 'immédiat',
    'recommandÃƒÂ©': 'recommandé',
    'renforcÃƒÂ©e': 'renforcée',
    'MÃƒÂ©canique': 'Mécanique',
    'MAGNÃƒâ€°TIQUE': 'MAGNÉTIQUE',
}

for k, v in replacements.items():
    content = content.replace(k, v)

# Fix icons using regex
content = re.sub(r"icon: '.*?THERMIQUE'", "icon: '🌡️', title: 'THERMIQUE'", content)
content = re.sub(r"icon: '.*?PRESSION'", "icon: '⚙️', title: 'PRESSION'", content)
content = re.sub(r"icon: '.*?PUISSANCE'", "icon: '⚡', title: 'PUISSANCE'", content)
content = re.sub(r"icon: '.*?VIBRATION'", "icon: '📳', title: 'VIBRATION'", content)
content = re.sub(r"icon: '.*?MAGNÉTIQUE'", "icon: '🧲', title: 'MAGNÉTIQUE'", content)
content = re.sub(r"icon: '.*?INFRA-ROUGE'", "icon: '🔆', title: 'INFRA-ROUGE'", content)
content = re.sub(r"icon: '.*?',\s*title: 'RISQUE CHAUFFAGE'", "icon: '🔥',\n            title: 'RISQUE CHAUFFAGE'", content)
content = re.sub(r"icon: '.*?',\s*title: 'RISQUE VIBRATION'", "icon: '📳',\n            title: 'RISQUE VIBRATION'", content)
content = re.sub(r"icon: '.*?TEMP\. CONTACT'", "icon: '🌡️', title: 'TEMP. CONTACT'", content)
content = re.sub(r"icon: '.*?COURANT'", "icon: '⚡', title: 'COURANT'", content)

# Any other Ã‚Â°C
content = content.replace('Ã‚Â°', '°')
content = content.replace('ÃƒÂ¢', 'â')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Fixed encoding issues.')
