import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const _kToken = 'api_auth_token';
  static const _kRole = 'api_user_role';

  static String? _authToken;
  static String? _userRole;

  static String? get authToken => _authToken;

  /// Rôle issu du dernier login (persisté), ex. `conception`, `technician`.
  static String? get savedUserRole => _userRole;

  static bool get isSuperAdmin =>
      (_userRole ?? '').toLowerCase() == 'superadmin';

  /// Super-admin ou admin d'entreprise (COMPANY_ADMIN).
  static bool get canManageFleet {
    final r = (_userRole ?? '').toLowerCase();
    return r == 'superadmin' || r == 'admin';
  }

  static Future<void> loadSavedAuth() async {
    final p = await SharedPreferences.getInstance();
    _authToken = p.getString(_kToken);
    _userRole = p.getString(_kRole);
  }

  static Future<void> saveAuth(String? token, String role) async {
    _authToken = (token != null && token.isNotEmpty) ? token : null;
    _userRole = role;
    final p = await SharedPreferences.getInstance();
    try {
      if (_authToken != null) {
        await p.setString(_kToken, _authToken!);
      } else {
        await p.remove(_kToken);
      }
      await p.setString(_kRole, role);
    } catch (e) {
      // Web : navigation privée / quota — le jeton reste en mémoire pour la session courante.
      debugPrint('ApiService.saveAuth: stockage local indisponible ($e)');
    }
  }

  static Future<void> clearAuth() async {
    _authToken = null;
    _userRole = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kRole);
  }

  static Map<String, String> _jsonHeaders({bool withAuth = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (withAuth && _authToken != null && _authToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_authToken';
    }
    return h;
  }

  /// Recharge le jeton depuis le stockage si la variable statique est vide (Flutter Web, nouvel onglet, etc.).
  static Future<void> ensureAuthTokenLoaded() async {
    if (_authToken != null && _authToken!.isNotEmpty) return;
    await loadSavedAuth();
  }

  /// En-têtes JSON avec `Authorization: Bearer …` après avoir tenté de restaurer la session.
  static Future<Map<String, String>> jsonHeadersAuthorized() async {
    await ensureAuthTokenLoaded();
    if (_authToken == null || _authToken!.isEmpty) {
      throw Exception(
        'Session non connectée : reconnectez-vous (compte super-admin ou admin).',
      );
    }
    return _jsonHeaders(withAuth: true);
  }

  /// Base API.
  ///
  /// En **Flutter Web**, l’UI est souvent sur un port aléatoire (ex. `http://localhost:64043/`)
  /// alors que **iot-backend** écoute sur le port **3001** : on appelle donc `http://<hôte>:3001/api`
  /// (même machine que la page).
  ///
  /// Surcharges :
  /// - `flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:3001`
  /// - `flutter run -d chrome --dart-define=API_PORT=3001` (hôte déduit de la page, port modifiable)
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE', defaultValue: '');
    if (fromEnv.isNotEmpty) {
      var o = fromEnv.trim();
      if (o.endsWith('/')) o = o.substring(0, o.length - 1);
      if (o.endsWith('/api')) return o;
      return '$o/api';
    }
    const apiPort = String.fromEnvironment('API_PORT', defaultValue: '3001');
    if (kIsWeb) {
      final scheme = Uri.base.scheme.isEmpty ? 'http' : Uri.base.scheme;
      var host = Uri.base.host;
      if (host.isEmpty) {
        host = '127.0.0.1';
      } else if (host == 'localhost') {
        // Évite souvent les refus de connexion (IPv6 ::1 vs API en IPv4) sous Windows.
        host = '127.0.0.1';
      }
      return '$scheme://$host:$apiPort/api';
    }
    return 'http://127.0.0.1:$apiPort/api';
  }

  /// Origine du serveur Node pour **Socket.IO** (même hôte/port que [baseUrl], sans `/api`).
  static String get socketBaseUrl {
    final u = baseUrl.trim();
    if (u.endsWith('/api/')) {
      return u.substring(0, u.length - 5);
    }
    if (u.endsWith('/api')) {
      return u.substring(0, u.length - 4);
    }
    return u;
  }

  static Never _throwApiError(http.Response response, String fallbackMessage) {
    Map<String, dynamic>? map;
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) map = decoded;
    } catch (_) {
      // Corps non-JSON : message générique ci-dessous.
    }
    if (response.statusCode == 401) {
      final m = map?['error']?.toString() ?? map?['message']?.toString() ?? 'Authentification requise';
      throw Exception(
        '$m Reconnectez-vous depuis l’écran de connexion.',
      );
    }
    if (map != null) {
      final message =
          map['error']?.toString() ?? map['message']?.toString();
      if (message != null && message.trim().isNotEmpty) {
        throw Exception(message.trim());
      }
    }
    throw Exception('$fallbackMessage (${response.statusCode})');
  }

  // --- Technicians ---
  
  static Future<List<Map<String, dynamic>>> getTechnicians() async {
    final response = await http.get(Uri.parse('$baseUrl/technicians'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Erreur de chargement des techniciens');
    }
  }

  /// Techniciens + concepteurs (+ personnel maintenance si super-admin). Auth fleet requis.
  static Future<List<Map<String, dynamic>>> getTeamDirectory() async {
    final response = await http.get(
      Uri.parse('$baseUrl/team-directory'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Erreur chargement répertoire équipe');
  }

  static Future<List<Map<String, dynamic>>> getTechniciansForClient(String clientId) async {
    final response = await http.get(Uri.parse('$baseUrl/clients/$clientId/technicians'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Erreur de chargement des techniciens du client');
    }
  }

  static Future<List<Map<String, dynamic>>> getMachines() async {
    final response = await http.get(Uri.parse('$baseUrl/machines'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Erreur de chargement des machines');
    }
  }

  static Future<Map<String, dynamic>?> getLatestTelemetry(String machineId) async {
    final response =
        await http.get(Uri.parse('$baseUrl/historique?machineId=$machineId'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      if (data.isEmpty) return null;
      return data.first as Map<String, dynamic>;
    } else {
      throw Exception('Erreur de chargement télémétrie machine');
    }
  }

  static Future<List<Map<String, dynamic>>> getTelemetryHistory(
    String machineId, {
    int limit = 20,
  }) async {
    final response =
        await http.get(Uri.parse('$baseUrl/historique?machineId=$machineId'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      final list = data.cast<Map<String, dynamic>>();
      if (list.length <= limit) return list;
      return list.take(limit).toList();
    } else {
      throw Exception('Erreur de chargement historique machine');
    }
  }

  static Future<Map<String, dynamic>> addTechnician(Map<String, dynamic> technicianData) async {
    final response = await http.post(
      Uri.parse('$baseUrl/technicians'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(technicianData),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      _throwApiError(response, 'Erreur lors de la création du technicien');
    }
  }

  static Future<Map<String, dynamic>> updateTechnician(String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$baseUrl/technicians/$id'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      _throwApiError(response, 'Erreur lors de la modification du technicien');
    }
  }

  static Future<void> deleteTechnician(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/technicians/$id'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Suppression du technicien impossible');
  }

  // -------------------------
  // CLIENTS
  // -------------------------

  static Future<List<Map<String, dynamic>>> getClients() async {
    final response = await http.get(Uri.parse('$baseUrl/clients'));
    if (response.statusCode == 200) {
      List<dynamic> body = json.decode(response.body);
      return body.map((dynamic item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Erreur lors du chargement des clients: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> addClient(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clients'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(data),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> addMachine(String clientId, Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clients/$clientId/machines'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(data),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> getMachinesForClient(String clientId) async {
    final response = await http.get(Uri.parse('$baseUrl/clients/$clientId/machines'));
    if (response.statusCode == 200) {
      List<dynamic> body = json.decode(response.body);
      return body.map((dynamic item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> updateClient(String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  static Future<void> deleteClient(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/clients/$id'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> getCompanies() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/companies'));
      if (response.statusCode == 200) {
        List<dynamic> body = json.decode(response.body);
        if (body is List) {
          return body.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (_) {}
    return await getClients();
  }

  // -------------------------
  // AUTH
  // -------------------------

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    String? apiMsg;
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map) {
        apiMsg = decoded['error']?.toString() ?? decoded['message']?.toString();
      }
    } catch (_) {}
    final trimmed = apiMsg?.trim();
    throw Exception(
      (trimmed != null && trimmed.isNotEmpty)
          ? trimmed
          : 'Erreur lors de la connexion (${response.statusCode})',
    );
  }

  static Future<Map<String, dynamic>> maintenanceLogin(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/maintenance-login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    String? apiMsg;
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map) {
        apiMsg = decoded['error']?.toString() ?? decoded['message']?.toString();
      }
    } catch (_) {}
    final trimmed = apiMsg?.trim();
    throw Exception(
      (trimmed != null && trimmed.isNotEmpty)
          ? trimmed
          : 'Connexion maintenance refusée (${response.statusCode})',
    );
  }

  static Future<Map<String, dynamic>> getMaintenanceWorkspace() async {
    final response = await http.get(
      Uri.parse('$baseUrl/maintenance/workspace'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Chargement espace maintenance impossible');
  }

  // -------------------------
  // IA PREDICTION
  // -------------------------
  static Future<Map<String, dynamic>> predictMachine(
    Map<String, dynamic> sensorPayload, {
    String machineId = 'MAC_A01',
  }) async {
    final body = <String, dynamic>{'machineId': machineId, ...sensorPayload};
    final response = await http.post(
      Uri.parse('$baseUrl/predict'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  static Future<Map<String, dynamic>> getModelMetrics() async {
    final response = await http.get(Uri.parse('$baseUrl/model-metrics'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  // -------------------------
  // REMOTE MACHINE CONTROL
  // -------------------------

  static Future<Map<String, dynamic>> getMachineInfo(String machineId) async {
    final response = await http.get(Uri.parse('$baseUrl/machines/$machineId/info'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Machine introuvable');
  }

  static Future<Map<String, dynamic>> updateMachine(
    String machineId,
    Map<String, dynamic> data,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/machines/$machineId'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Mise à jour machine refusée');
  }

  static Future<Map<String, dynamic>> stopMachine(String machineId, {String? reason, String? stoppedBy}) async {
    final body = <String, dynamic>{
      'machineId': machineId,
      'action': 'emergency_stop',
      if (reason != null) 'reason': reason,
      if (stoppedBy != null) 'stoppedBy': stoppedBy,
    };
    final response = await http.post(
      Uri.parse('$baseUrl/machines/$machineId/stop'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Erreur arrêt machine (${response.statusCode})');
  }

  static Future<void> deleteMachine(String machineId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/machines/$machineId'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Suppression de la machine impossible');
  }

  // -------------------------
  // CONCEPTIONS (USERS)
  // -------------------------

  static Future<List<Map<String, dynamic>>> getConceptions() async {
    final response = await http.get(
      Uri.parse('$baseUrl/conceptions'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Erreur de chargement des conceptions');
  }

  static Future<Map<String, dynamic>> addConception(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conceptions'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Enregistrement du document refusé');
  }

  // -------------------------
  // MAINTENANCE & CONCEPTEURS
  // -------------------------

  static Future<List<Map<String, dynamic>>> getMaintenanceOrders() async {
    final response = await http.get(
      Uri.parse('$baseUrl/maintenance-orders'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Erreur chargement ordres de maintenance');
  }

  static Future<Map<String, dynamic>> createMaintenanceOrder(
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/maintenance-orders'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Création ordre maintenance refusée');
  }

  static Future<Map<String, dynamic>> updateMaintenanceOrder(
    String id,
    Map<String, dynamic> body,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/maintenance-orders/$id'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Mise à jour ordre maintenance refusée');
  }

  static Future<Map<String, dynamic>> updateMaintenanceOrderStatus(
    String id,
    String status, {
    Map<String, dynamic>? extraPayload,
  }) async {
    final body = <String, dynamic>{'status': status, ...?extraPayload};
    final response = await http.patch(
      Uri.parse('$baseUrl/maintenance-orders/$id/status'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Changement de statut maintenance refusé');
  }

  static Future<Map<String, dynamic>> startMaintenanceControl(
    String machineId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/machines/$machineId/maintenance-control'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Prise en charge maintenance refusée');
  }

  static Future<Map<String, dynamic>> finishMaintenanceControl(
    String machineId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/machines/$machineId/maintenance-control/finish'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Fin de contrôle maintenance refusée');
  }

  static Future<List<Map<String, dynamic>>> getDiagnosticScenarios() async {
    final response = await http.get(
      Uri.parse('$baseUrl/diagnostic-interventions/scenarios'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Chargement scénarios impossible');
  }

  static Future<List<Map<String, dynamic>>> getDiagnosticInterventions() async {
    final response = await http.get(
      Uri.parse('$baseUrl/diagnostic-interventions'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Chargement interventions diagnostic impossible');
  }

  static Future<Map<String, dynamic>> createDiagnosticIntervention(
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/diagnostic-interventions'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Création intervention diagnostic refusée');
  }

  static Future<void> addDiagnosticMessage(
    String interventionId,
    String content, {
    String? authorName,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/messages'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({
        'content': content,
        if (authorName != null && authorName.isNotEmpty) 'authorName': authorName,
      }),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Envoi message diagnostic refusé');
  }

  static Future<void> addCoordinationNote(
    String interventionId,
    String content, {
    String? authorName,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/coordination'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({
        'content': content,
        if (authorName != null && authorName.isNotEmpty) 'authorName': authorName,
      }),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Envoi note de coordination refusé');
  }

  static Future<void> addDiagnosticStep(
    String interventionId,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/steps'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Ajout étape diagnostic refusé');
  }

  static Future<void> markDiagnosticStepOk(
    String interventionId,
    String stepId, {
    String? note,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/steps/$stepId/ok'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({'note': note ?? ''}),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Validation étape diagnostic refusée');
  }

  static Future<void> nextDiagnosticStep(String interventionId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/next'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Passage étape suivante refusé');
  }

  static Future<void> setDiagnosticDecision(
    String interventionId, {
    required String finalDecision,
    String? finalNote,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/decision'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({
        'finalDecision': finalDecision,
        'finalNote': finalNote ?? '',
      }),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Enregistrement décision finale refusé');
  }

  static Future<void> setDiagnosticStatus(String interventionId, String status) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/status'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({'status': status}),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Changement statut diagnostic refusé');
  }

  static Future<void> deleteDiagnosticIntervention(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/diagnostic-interventions/$id'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Suppression de l\'intervention refusée');
  }

  static Future<void> reassignDiagnosticTechnician(String id, {required String technicianId, required String technicianName}) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/diagnostic-interventions/$id/reassign'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({
        'technicianId': technicianId,
        'technicianName': technicianName,
      }),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Réassignation du technicien refusée');
  }

  static Future<List<Map<String, dynamic>>> getConcepteurs() async {
    final response = await http.get(
      Uri.parse('$baseUrl/concepteurs'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Erreur chargement concepteurs');
  }

  static Future<Map<String, dynamic>> getConcepteur(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/concepteurs/${Uri.encodeComponent(id)}'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Concepteur introuvable');
  }

  /// Machines + client pour le tableau de bord conception (compte connecté CONCEPTION).
  static Future<Map<String, dynamic>> getConceptionWorkspace() async {
    final response = await http.get(
      Uri.parse('$baseUrl/conception/workspace'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Chargement espace conception impossible');
  }

  static Future<Map<String, dynamic>> addConcepteur(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/concepteurs'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Création du concepteur refusée');
  }

  static Future<Map<String, dynamic>> updateConcepteur(String id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$baseUrl/concepteurs/${Uri.encodeComponent(id)}'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Mise à jour du concepteur refusée');
  }

  static Future<void> deleteConcepteur(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/concepteurs/${Uri.encodeComponent(id)}'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Suppression du concepteur impossible');
  }

  /// Personnel maintenance (fiches Mongo) — réservé super-admin API.
  static Future<List<Map<String, dynamic>>> getMaintenanceAgents() async {
    final response = await http.get(
      Uri.parse('$baseUrl/maintenance-agents'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Erreur chargement personnel maintenance');
  }

  static Future<Map<String, dynamic>> addMaintenanceAgent(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/maintenance-agents'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Création du profil maintenance refusée');
  }

  static Future<Map<String, dynamic>> updateMaintenanceAgent(String id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$baseUrl/maintenance-agents/${Uri.encodeComponent(id)}'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Mise à jour du profil maintenance refusée');
  }

  static Future<void> deleteMaintenanceAgent(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/maintenance-agents/${Uri.encodeComponent(id)}'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Suppression du profil maintenance impossible');
  }

  // -------------------------
  // CHAT
  // -------------------------

  static Future<List<Map<String, dynamic>>> getChatMessages(
    String roomId, {
    int limit = 200,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/messages?roomId=$roomId&limit=$limit'),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Erreur de chargement des messages');
  }

  static Future<List<Map<String, dynamic>>> getTechnicianConversations(
    String technicianId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/technician-conversations?technicianId=$technicianId'),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Erreur de chargement des conversations technicien');
  }

  static Future<List<Map<String, dynamic>>> getClientConversations(
    String clientId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/client-conversations?clientId=$clientId'),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Erreur de chargement des conversations client');
  }

  static Future<List<Map<String, dynamic>>> getConceptionConversations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/conception-conversations'),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Erreur de chargement des conversations conception');
  }
}
