/// Modèle d’état du tableau de bord admin (couche Model MVC).
class DashboardState {
  const DashboardState({
    this.clientCount = 0,
    this.machineCount = 0,
    this.machinesEnLigneCount = 0,
    this.concepteurCount = 0,
    this.documentCount = 0,
    this.techCount = 0,
    this.riskPct = 0,
    this.stablePct = 100,
    this.riskMode = 'Aucun risque majeur',
    this.machinesRunningOnMap = 0,
    this.machinesTracked = 0,
    this.fleetMapMarkers = const [],
    this.isLoadingCounts = true,
  });

  final int clientCount;
  final int machineCount;
  final int machinesEnLigneCount;
  final int concepteurCount;
  final int documentCount;
  final int techCount;
  final int riskPct;
  final int stablePct;
  final String riskMode;
  final int machinesRunningOnMap;
  final int machinesTracked;
  final List<Map<String, dynamic>> fleetMapMarkers;
  final bool isLoadingCounts;

  static const initial = DashboardState();

  DashboardState copyWith({
    int? clientCount,
    int? machineCount,
    int? machinesEnLigneCount,
    int? concepteurCount,
    int? documentCount,
    int? techCount,
    int? riskPct,
    int? stablePct,
    String? riskMode,
    int? machinesRunningOnMap,
    int? machinesTracked,
    List<Map<String, dynamic>>? fleetMapMarkers,
    bool? isLoadingCounts,
  }) {
    return DashboardState(
      clientCount: clientCount ?? this.clientCount,
      machineCount: machineCount ?? this.machineCount,
      machinesEnLigneCount: machinesEnLigneCount ?? this.machinesEnLigneCount,
      concepteurCount: concepteurCount ?? this.concepteurCount,
      documentCount: documentCount ?? this.documentCount,
      techCount: techCount ?? this.techCount,
      riskPct: riskPct ?? this.riskPct,
      stablePct: stablePct ?? this.stablePct,
      riskMode: riskMode ?? this.riskMode,
      machinesRunningOnMap: machinesRunningOnMap ?? this.machinesRunningOnMap,
      machinesTracked: machinesTracked ?? this.machinesTracked,
      fleetMapMarkers: fleetMapMarkers ?? this.fleetMapMarkers,
      isLoadingCounts: isLoadingCounts ?? this.isLoadingCounts,
    );
  }
}
