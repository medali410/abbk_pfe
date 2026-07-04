import 'package:flutter/material.dart';
import 'chat_theme.dart';

class ChatLayout extends StatelessWidget {
  final Widget sidebar;
  final Widget mainArea;
  final Widget? infoPanel;
  final bool showSidebarOnMobile;
  final bool showInfoPanelOnMobile;

  const ChatLayout({
    super.key,
    required this.sidebar,
    required this.mainArea,
    this.infoPanel,
    this.showSidebarOnMobile = true,
    this.showInfoPanelOnMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineBorder = isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFCD7F32).withOpacity(0.15);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        final isPlatformTablet = constraints.maxWidth > 600 && constraints.maxWidth <= 900;
        
        if (isDesktop) {
          // 3-pane layout for desktop
          return Row(
            children: [
              SizedBox(width: 320, child: sidebar),
              Container(width: 1, color: lineBorder),
              Expanded(child: mainArea),
              if (infoPanel != null) ...[
                Container(width: 1, color: lineBorder),
                SizedBox(width: 280, child: infoPanel!),
              ],
            ],
          );
        } else if (isPlatformTablet) {
          // 2-pane layout for tablet (hide info panel)
          return Row(
            children: [
              SizedBox(width: 300, child: sidebar),
              Container(width: 1, color: lineBorder),
              Expanded(child: mainArea),
            ],
          );
        } else {
          // 1-pane layout for mobile
          if (showInfoPanelOnMobile && infoPanel != null) {
            return infoPanel!;
          }
          if (showSidebarOnMobile) {
            return sidebar;
          }
          return mainArea;
        }
      },
    );
  }
}
