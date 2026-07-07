import 'dart:io';

void main() {
  var f = File(r'c:\Users\Administrator\abbk_pfe_new\dali-pfe\lib\concepteur_dashboard_page.dart');
  var c = f.readAsStringSync();
  var colors = [
    'primaryColor',
    'mutedTextColor',
    'textColor',
    'bgColor',
    'cardColor',
    'sidebarColor',
    'accentColor',
    'ThemeService().isDarkMode',
  ];
  int index = 0;
  while (index < c.length) {
    int nextMatch = c.length;
    for (var col in colors) {
      int m = c.indexOf(col, index);
      if (m != -1 && m < nextMatch) {
        nextMatch = m;
      }
    }
    if (nextMatch == c.length) break;

    // Scan backwards from the match to find 'const '
    for (int i = nextMatch; i >= 0; i--) {
      // stop if we hit something that breaks the expression boundary
      if (c[i] == ';' || c[i] == '{' || c[i] == '}') {
        break;
      }
      if (i >= 6 && c.substring(i - 6, i) == 'const ') {
        c = c.substring(0, i - 6) + '      ' + c.substring(i);
        break;
      }
    }
    index = nextMatch + 8;
  }

  // Double check and fix nested consts (e.g. const Center(child: CircularProgressIndicator...))
  // A simple pass again to catch the missed ones if the boundary didn't break.
  index = 0;
  while (index < c.length) {
    int nextMatch = c.length;
    for (var col in colors) {
      int m = c.indexOf(col, index);
      if (m != -1 && m < nextMatch) {
        nextMatch = m;
      }
    }
    if (nextMatch == c.length) break;

    for (int i = nextMatch; i >= 0; i--) {
      if (c[i] == ';' || c[i] == '{' || c[i] == '}') {
        break;
      }
      if (i >= 6 && c.substring(i - 6, i) == 'const ') {
        c = c.substring(0, i - 6) + '      ' + c.substring(i);
        break;
      }
    }
    index = nextMatch + 8;
  }

  f.writeAsStringSync(c);
  print('Fixed!');
}
