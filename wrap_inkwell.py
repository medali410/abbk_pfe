import sys

with open('dali-pfe/lib/concepteur_dashboard_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

method = '''
  void _openMachineDetail(Map<String, dynamic> m) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MachineDetailAiPage(
        machineId: _machineIdOf(m),
        machineName: _machineNameOf(m),
        clientId: (m['clientId'] ?? m['companyId'] ?? '').toString(),
        location: (m['location'] ?? '').toString(),
        viewerRole: ApiService.savedUserRole,
        viewerName: _profileDisplayName,
      ),
    ));
  }
'''

if '_openMachineDetail' not in content:
    content = content.replace('  String _pickFirstString(Map<String, dynamic> src, List<String> keys) {', method + '\n  String _pickFirstString(Map<String, dynamic> src, List<String> keys) {')

def replace_containers(text):
    out = []
    lines = text.split('\n')
    i = 0
    while i < len(lines):
        line = lines[i]
        # Match `return Container(` inside the itemBuilder for machines
        if 'return Container(' in line and 'padding: const EdgeInsets.all(12),' in lines[i+1] and 'decoration: BoxDecoration(' in lines[i+2]:
            indent = len(line) - len(line.lstrip())
            prefix = line[:indent]
            out.append(prefix + 'return InkWell(')
            out.append(prefix + '  onTap: () => _openMachineDetail(m),')
            out.append(prefix + '  borderRadius: BorderRadius.circular(12),')
            out.append(prefix + '  child: Container(')
            
            # Now find the matching `);` at the same indentation level
            i += 1
            bracket_count = 1
            while i < len(lines):
                curr = lines[i]
                if curr.startswith(prefix + ');'):
                    out.append(prefix + '  ),')
                    out.append(prefix + ');')
                    break
                else:
                    out.append(curr)
                i += 1
        else:
            out.append(line)
        i += 1
    return '\n'.join(out)

new_content = replace_containers(content)

with open('dali-pfe/lib/concepteur_dashboard_page.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)

print("Done wrapping with InkWell")
