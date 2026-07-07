import 'dart:io';

void main() {
  var path = r'c:\Users\Administrator\abbk_pfe_new\dali-pfe\lib\concepteur_dashboard_page.dart';
  var c = File(path).readAsStringSync();
  
  // Replace explicit known exact single-line occurrences first
  c = c.replaceAll('const Icon(Icons.precision_manufacturing, color: primaryColor)', 'Icon(Icons.precision_manufacturing, color: primaryColor)');
  c = c.replaceAll('const Icon(Icons.verified_user_outlined, color: primaryColor)', 'Icon(Icons.verified_user_outlined, color: primaryColor)');
  c = c.replaceAll('const Icon(Icons.info_outline, color: primaryColor)', 'Icon(Icons.info_outline, color: primaryColor)');
  c = c.replaceAll('const Icon(Icons.people_outline_rounded, color: primaryColor)', 'Icon(Icons.people_outline_rounded, color: primaryColor)');
  c = c.replaceAll('const Icon(Icons.build_circle_outlined, color: primaryColor)', 'Icon(Icons.build_circle_outlined, color: primaryColor)');
  c = c.replaceAll('const Icon(Icons.shopping_cart_checkout, color: primaryColor)', 'Icon(Icons.shopping_cart_checkout, color: primaryColor)');
  c = c.replaceAll('const Icon(Icons.engineering_rounded, color: primaryColor)', 'Icon(Icons.engineering_rounded, color: primaryColor)');
  c = c.replaceAll('const Icon(Icons.logout_rounded, color: mutedTextColor, size: 20)', 'Icon(Icons.logout_rounded, color: mutedTextColor, size: 20)');
  c = c.replaceAll('const Icon(Icons.clear, color: mutedTextColor, size: 18)', 'Icon(Icons.clear, color: mutedTextColor, size: 18)');
  c = c.replaceAll('const Icon(Icons.filter_list, color: primaryColor, size: 20)', 'Icon(Icons.filter_list, color: primaryColor, size: 20)');
  c = c.replaceAll('const Icon(Icons.more_vert, color: mutedTextColor, size: 18)', 'Icon(Icons.more_vert, color: mutedTextColor, size: 18)');
  c = c.replaceAll('const Icon(Icons.view_in_ar, color: primaryColor)', 'Icon(Icons.view_in_ar, color: primaryColor)');
  c = c.replaceAll('const Icon(Icons.close, color: mutedTextColor)', 'Icon(Icons.close, color: mutedTextColor)');
  
  // also precision_manufacturing with mutedTextColor
  c = c.replaceAll('const Icon(Icons.precision_manufacturing, color: mutedTextColor, size: 36,)', 'Icon(Icons.precision_manufacturing, color: mutedTextColor, size: 36,)');
  c = c.replaceAllMapped(RegExp(r'const\s+Icon\(\s*Icons\.precision_manufacturing,\s*color:\s*mutedTextColor,'), (m) => 'Icon(Icons.precision_manufacturing, color: mutedTextColor,');
  
  c = c.replaceAll('style: const TextStyle(color: textColor', 'style: TextStyle(color: textColor');
  c = c.replaceAll('style: const TextStyle(color: primaryColor', 'style: TextStyle(color: primaryColor');
  c = c.replaceAll('const Text(\'FERMER\', style: TextStyle(color: primaryColor))', 'Text(\'FERMER\', style: TextStyle(color: primaryColor))');

  c = c.replaceAll('const Center(child: CircularProgressIndicator(color: primaryColor))', 'Center(child: CircularProgressIndicator(color: primaryColor))');

  int passes = 0;
  while(passes < 3) {
    c = c.replaceAllMapped(RegExp(r'const\s+(Icon|Text|Center|SizedBox|Padding|CircularProgressIndicator|BorderSide|OutlineInputBorder|TextStyle)\s*\(([\s\S]*?)(primaryColor|mutedTextColor|textColor)') , (match) {
      if (match.group(2)!.contains(';')) return match.group(0)!; // Safety heuristic
      return '${match.group(1)}(${match.group(2)}${match.group(3)}';
    });
    passes++;
  }

  File(path).writeAsStringSync(c);
  print('DART_FIX_OK');
}
