import codecs

path = r'C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\client_dashboard_page.dart'

with codecs.open(path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('\r\n', '\n')

target = '''    if (mag >= 80.0) {
      newMode = 'danger';
      risques.add("Magnétique critique (>= 80 mT)");
    } else if (mag >= 50.0) {
      if (newMode == 'normal') newMode = 'risque';
      risques.add("Magnétique anormal (>= 50 mT)");
    }'''

if target in content:
    content = content.replace(target, '')
    content = content.replace('\n', '\r\n')
    with codecs.open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS')
else:
    # Try finding with any characters
    import re
    pattern = r'if \(mag >= 80\.0\)\s*\{.*?\}\s*else\s+if\s*\(mag >= 50\.0\)\s*\{.*?\}'
    content, count = re.subn(pattern, '', content, flags=re.DOTALL)
    if count > 0:
        content = content.replace('\n', '\r\n')
        with codecs.open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f'SUCCESS (regex matched {count} times)')
    else:
        print('FAIL')
