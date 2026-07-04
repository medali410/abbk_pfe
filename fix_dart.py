import sys

file_path = r'C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\client_dashboard_page.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_block = """                Expanded(
                  flex: 1,
                  child: _buildSubpageHeader(
                    title: 'Analyse IA',
                    subtitle: ' • ',
                    onBack: () {},
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _outlineVariant.withOpacity(0.3)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: mid,
                        dropdownColor: _surfaceContainerHigh,
                        style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600),
                        icon: const Icon(Icons.arrow_drop_down, color: _secondary),
                        items: machines.map((m) {
                          final id = _clientMachineId(m);
                          final name = _clientMachineName(m);
                          return DropdownMenuItem(
                            value: id,
                            child: Text(
                              ' • ',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _iaSelectedMachine = machines.firstWhere((m) => _clientMachineId(m) == val);
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
"""

# The above block uses valid dart syntax directly
replacement_lines = [line + '\n' for line in new_block.split('\n')][:-1]

# Reconstruct file
lines = lines[:1526] + replacement_lines + lines[1547:]

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('Done!')
