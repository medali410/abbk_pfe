import re

with open('dali-pfe/lib/machine_detail_ai_page.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

patterns = [r'=\s*_bg\b', r'=\s*_panel\b', r'=\s*_panel2\b', r'=\s*_panel3\b', r'=\s*_text\b', r'=\s*_muted\b', r'=\s*_orange\b', r'=\s*_cyan\b', r'=\s*_green\b', r'=\s*_red\b']

for i, line in enumerate(lines):
    for pat in patterns:
        if re.search(pat, line):
            print(f"Line {i+1}: {line.strip()}")
