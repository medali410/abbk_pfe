import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';

class AiAnalysisView extends StatefulWidget {
  final String machineId;
  final String machineName;
  final String motorType;

  const AiAnalysisView({
    super.key,
    required this.machineId,
    required this.machineName,
    this.motorType = 'EL_M',
  });

  @override
  State<AiAnalysisView> createState() => _AiAnalysisViewState();
}

