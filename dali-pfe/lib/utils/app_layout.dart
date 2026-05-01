import 'package:flutter/widgets.dart';

/// Largeur en dessous de laquelle on privilégie une mise en page type téléphone
/// (colonnes, marges réduites, pas de rangées serrées à 6 colonnes).
const double kMobileLayoutBreakpoint = 720;

bool isMobileLayoutWidth(double width) => width < kMobileLayoutBreakpoint;

bool isMobileLayout(BuildContext context) =>
    isMobileLayoutWidth(MediaQuery.sizeOf(context).width);
