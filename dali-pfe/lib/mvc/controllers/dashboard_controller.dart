import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
import '../models/dashboard_state.dart';

/// Contrôleur MVC du tableau de bord admin : logique + état, sans widgets.
class DashboardController extends ChangeNotifier {
  DashboardState state = DashboardState.initial;

  Future<bool> ensureAuthSession() async {
    await ApiService.ensureAuthTokenLoaded();
    return (ApiService.authToken ?? '').isNotEmpty;
  }

  Future<void> loadGlobalStats() async {
    state = state.copyWith(isLoadingCounts: true);
    notifyListeners();

    try {
      await ApiService.ensureAuthTokenLoaded();
      final hasToken = (ApiService.authToken ?? '').isNotEmpty;
      final machinesFuture = ApiService.getCatalogMachines();
      final kpisFuture =
          hasToken ? ApiService.getDashboardKpis() : Future.value(<String, int>{});
      final fleetFuture = hasToken
          ? ApiService.getDashboardFleetOverview()
          : Future.value(<String, dynamic>{});

      Map<String, int> kpis = {};
      Map<String, dynamic> fleet = {};
      List<Map<String, dynamic>> machines = [];

      try {
        kpis = await kpisFuture;
      } catch (e) {
        debugPrint('Dashboard KPI counts: $e');
      }
      try {
        fleet = await fleetFuture;
      } catch (e) {
        debugPrint('Dashboard fleet overview: $e');
      }
      try {
        machines = await machinesFuture;
      } catch (e) {
        debugPrint('Dashboard machines: $e');
      }

      var riskPct = (fleet['riskPct'] as num?)?.round() ?? 0;
      var stablePct = (fleet['stablePct'] as num?)?.round() ?? 100;
      var riskMode = (fleet['riskMode'] ?? 'Aucun risque majeur').toString();

      if (!fleet.containsKey('riskPct')) {
        final riskData = await _computeRiskStats(machines);
        riskPct = riskData.riskPct;
        stablePct = riskData.stablePct;
        riskMode = riskData.riskMode;
      }

      final rawMarkers = fleet['markers'];
      final markers = rawMarkers is List
          ? rawMarkers
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      if (machines.isNotEmpty) {
        if ((kpis['machines'] ?? 0) == 0) {
          kpis['machines'] = machines.length;
        }
        if (!kpis.containsKey('machinesEnLigne')) {
          kpis['machinesEnLigne'] = machines.where(_isMachineRunning).length;
        }
      }
      if (kpis.isEmpty || (kpis['clients'] ?? 0) == 0) {
        try {
          final clients = await ApiService.getClients();
          if (clients.isNotEmpty) kpis['clients'] = clients.length;
        } catch (_) {}
      }

      state = state.copyWith(
        clientCount: kpis['clients'] ?? 0,
        machineCount: kpis['machines'] ?? machines.length,
        machinesEnLigneCount:
            kpis['machinesEnLigne'] ?? machines.where(_isMachineRunning).length,
        concepteurCount: kpis['concepteurs'] ?? 0,
        documentCount: kpis['documents'] ?? 0,
        techCount: kpis['technicians'] ?? 0,
        riskPct: riskPct,
        stablePct: stablePct,
        riskMode: riskMode,
        machinesTracked:
            (fleet['machinesTracked'] as num?)?.toInt() ?? machines.length,
        machinesRunningOnMap:
            (fleet['machinesRunning'] as num?)?.toInt() ?? markers.length,
        fleetMapMarkers: markers,
        isLoadingCounts: false,
      );
    } catch (e, st) {
      debugPrint('Dashboard KPI: $e\n$st');
      state = state.copyWith(isLoadingCounts: false);
    }
    notifyListeners();
  }

  bool _isMachineRunning(Map<String, dynamic> m) {
    final s = (m['status'] ?? '').toString().toUpperCase();
    return s == 'RUNNING' || s == 'NORMAL';
  }

  String _extractMachineId(Map<String, dynamic> m) {
    return (m['id'] ?? m['machineId'] ?? m['_id'] ?? '').toString();
  }

  double _toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  int _riskFromTelemetry(Map<String, dynamic>? latest) {
    if (latest == null) return 0;
    final metricsRaw = latest['metrics'];
    Map<String, dynamic>? metrics;
    if (metricsRaw is Map<String, dynamic>) {
      metrics = metricsRaw;
    } else if (metricsRaw is Map) {
      metrics = Map<String, dynamic>.from(metricsRaw);
    }

    final fs = latest['failureScenario'];
    if (fs is Map) {
      final scenarioProb = fs['scenarioProbPanne'];
      if (scenarioProb != null) {
        final d = _toDouble(scenarioProb, 0);
        return d <= 1 ? (d * 100).round().clamp(0, 100) : d.round().clamp(0, 100);
      }
    }

    final direct = latest['prob_panne'] ??
        latest['failureProbability'] ??
        latest['panne_probability'] ??
        latest['scenarioProbPanne'];
    if (direct != null) {
      final d = _toDouble(direct, 0);
      return d <= 1 ? (d * 100).round().clamp(0, 100) : d.round().clamp(0, 100);
    }

    final t = _toDouble(latest['temperature'] ?? metrics?['thermal'], 0);
    final p = _toDouble(latest['pressure'] ?? metrics?['pressure'], 0);
    final v = _toDouble(latest['vibration'] ?? metrics?['vibration'], 0);
    final power = _toDouble(latest['power'] ?? metrics?['power'], 0);

    var score = 0.0;
    if (t >= 85) {
      score += 35;
    } else if (t >= 70) {
      score += 22;
    } else if (t >= 60) {
      score += 10;
    }
    if (p >= 6.0 || (p > 0 && p <= 0.8)) {
      score += 25;
    } else if (p >= 4.8 || (p > 0 && p <= 1.2)) {
      score += 12;
    }
    if (v >= 8.0) {
      score += 30;
    } else if (v >= 4.0) {
      score += 16;
    }
    if (power >= 6500) {
      score += 20;
    } else if (power >= 4500) {
      score += 10;
    }
    return score.round().clamp(0, 100);
  }

  String _riskModeFromTelemetry(Map<String, dynamic>? latest) {
    if (latest == null) return 'Inconnu';
    final raw = (latest['panne_type'] ??
            latest['scenarioLabel'] ??
            latest['scenario_label'] ??
            latest['ml_scenario'] ??
            '')
        .toString()
        .trim();
    if (raw.isNotEmpty && !raw.toLowerCase().contains('erreur serveur ml')) {
      return raw;
    }

    final metricsRaw = latest['metrics'];
    Map<String, dynamic>? metrics;
    if (metricsRaw is Map<String, dynamic>) {
      metrics = metricsRaw;
    } else if (metricsRaw is Map) {
      metrics = Map<String, dynamic>.from(metricsRaw);
    }
    final t = _toDouble(latest['temperature'] ?? metrics?['thermal'], 0);
    final v = _toDouble(latest['vibration'] ?? metrics?['vibration'], 0);
    final p = _toDouble(latest['pressure'] ?? metrics?['pressure'], 0);
    final power = _toDouble(latest['power'] ?? metrics?['power'], 0);

    if (power >= 5500 || p >= 6.0) return 'Risque électrique';
    if (v >= 6.0) return 'Risque mécanique';
    if (t >= 85) return 'Surchauffe';
    return 'Aucun risque majeur';
  }

  Future<({int riskPct, int stablePct, String riskMode})> _computeRiskStats(
    List<Map<String, dynamic>> machines,
  ) async {
    if (machines.isEmpty) {
      return (riskPct: 0, stablePct: 100, riskMode: 'Aucun risque majeur');
    }

    final ids = machines.map(_extractMachineId).where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) {
      return (riskPct: 0, stablePct: 100, riskMode: 'Aucun risque majeur');
    }

    final latestList = await Future.wait(
      ids.map((id) async {
        try {
          return await ApiService.getLatestTelemetry(id);
        } catch (_) {
          return null;
        }
      }),
    );

    var riskSum = 0;
    var stableCount = 0;
    var worstRisk = -1;
    var worstMode = 'Aucun risque majeur';

    for (final latest in latestList) {
      final r = _riskFromTelemetry(latest);
      riskSum += r;
      if (r < 40) stableCount++;
      if (r > worstRisk) {
        worstRisk = r;
        worstMode = _riskModeFromTelemetry(latest);
      }
    }

    final avgRisk = (riskSum / latestList.length).round().clamp(0, 100);
    final stablePct =
        ((stableCount * 100) / latestList.length).round().clamp(0, 100);
    return (riskPct: avgRisk, stablePct: stablePct, riskMode: worstMode);
  }

  @override
  void dispose() {
    super.dispose();
  }
}
