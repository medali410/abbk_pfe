import os
import re

file_path = 'lib/widgets/chat/chat_sidebar.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

# Replace getters with methods
text = re.sub(r'Color get _bg\s*=>.*?;', 'Color _bg(BuildContext context) => ChatTheme.of(context).sidebar;', text)
text = re.sub(r'Color get _text\s*=>.*?;', 'Color _text(BuildContext context) => ChatTheme.of(context).text;', text)
text = re.sub(r'Color get _muted\s*=>.*?;', 'Color _muted(BuildContext context) => ChatTheme.of(context).muted;', text)
text = re.sub(r'Color get _active\s*=>.*?;', 'Color _active(BuildContext context) => ChatTheme.of(context).activeItem;', text)
text = re.sub(r'Color get _border\s*=>.*?;', 'Color _border(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : const Color(0xFFCD7F32).withOpacity(0.2);', text)
text = re.sub(r'Color get _inputBg\s*=>.*?;', 'Color _inputBg(BuildContext context) => ChatTheme.of(context).bg.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.5 : 0.8);', text)
text = re.sub(r'Color get _divider\s*=>.*?;', 'Color _divider(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFCD7F32).withOpacity(0.15);', text)

# Replace occurrences
text = re.sub(r'\b_bg\b', '_bg(context)', text)
text = re.sub(r'\b_text\b', '_text(context)', text)
text = re.sub(r'\b_muted\b', '_muted(context)', text)
text = re.sub(r'\b_active\b', '_active(context)', text)
text = re.sub(r'\b_border\b', '_border(context)', text)
text = re.sub(r'\b_inputBg\b', '_inputBg(context)', text)
text = re.sub(r'\b_divider\b', '_divider(context)', text)

# Fix declarations which were accidentally replaced
text = text.replace('Color _bg(context)(BuildContext context)', 'Color _bg(BuildContext context)')
text = text.replace('Color _text(context)(BuildContext context)', 'Color _text(BuildContext context)')
text = text.replace('Color _muted(context)(BuildContext context)', 'Color _muted(BuildContext context)')
text = text.replace('Color _active(context)(BuildContext context)', 'Color _active(BuildContext context)')
text = text.replace('Color _border(context)(BuildContext context)', 'Color _border(BuildContext context)')
text = text.replace('Color _inputBg(context)(BuildContext context)', 'Color _inputBg(BuildContext context)')
text = text.replace('Color _divider(context)(BuildContext context)', 'Color _divider(BuildContext context)')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)
    
print("Refactor complete")
