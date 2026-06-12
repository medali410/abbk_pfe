import os

filepath = r"C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\concepteur_dashboard_page.dart"
with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

replacement_text = """                          if (techM.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: techM.map((m) {
                                return InkWell(
                                  onTap: () => _showMachineMiniDetails(context, m),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.1),
                                      border: Border.all(color: primaryColor.withOpacity(0.3)),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.precision_manufacturing, size: 12, color: primaryColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          _machineNameOf(m),
                                          style: GoogleFonts.inter(color: primaryColor, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],"""

start_str = "if (techM.isNotEmpty) ...["
end_str = "], // end techM"

# Let's find the exact index.
idx_start = content.find("if (techM.isNotEmpty) ...[")
if idx_start != -1:
    idx_end = content.find("],", idx_start)
    if idx_end != -1:
        # Include '],'
        old_block = content[idx_start:idx_end+2]
        content = content.replace(old_block, replacement_text)
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(content)
        print("Replacement successful.")
    else:
        print("End not found.")
else:
    print("Start not found.")

