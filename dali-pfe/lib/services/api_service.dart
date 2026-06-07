import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const _kToken = 'api_auth_token';
  static const _kRole = 'api_user_role';
  static const _kClientId = 'api_client_id';
  static const _kClientName = 'api_client_name';
  static const _kClientEmail = 'api_client_email';
  static const _kClientLocation = 'api_client_location';
  static const _kClientPhotoUrl = 'api_client_photo_url';
  static const _kClientBackgroundUrl = 'api_client_background_url';
  static const _kTechnicianProfileJson = 'api_technician_profile_json';
  static const _kConcepteurProfileJson = 'api_concepteur_profile_json';

  static String? _authToken;
  static String? _userRole;
  static String? _savedClientId;
  static String? _savedClientName;
  static String? _savedClientEmail;
  static String? _savedClientLocation;
  static String? _savedClientPhotoUrl;
  static String? _savedClientBackgroundUrl;

  static String? get authToken => _authToken;
  static String? get savedClientId => _savedClientId;
  static String? get savedClientName => _savedClientName;
  static String? get savedClientEmail => _savedClientEmail;
  static String? get savedClientLocation => _savedClientLocation;
  static String? get savedClientPhotoUrl => _savedClientPhotoUrl;
  static String? get savedClientBackgroundUrl => _savedClientBackgroundUrl;

  /// Rôle issu du dernier login (persisté), ex. `conception`, `technician`.
  static String? get savedUserRole => _userRole;

  /// Profil technicien (persisté) : `_id`, `technicianId`, `companyId`, etc. — pour rechargement web / calendrier.
  static Map<String, dynamic>? _savedTechnicianProfile;
  static Map<String, dynamic>? get savedTechnicianProfile => _savedTechnicianProfile;

  /// Profil concepteur (persisté) : nom, email, concepteurId, etc.
  static Map<String, dynamic>? _savedConcepteurProfile;
  static Map<String, dynamic>? get savedConcepteurProfile => _savedConcepteurProfile;

  static bool get isSuperAdmin =>
      (_userRole ?? '').toLowerCase() == 'superadmin';

  /// Super-admin et admin entreprise : même acteur (gestion flotte).
  static bool get isFleetAdmin => canManageFleet;

  /// Super-admin ou admin d'entreprise (COMPANY_ADMIN) — même périmètre UI / API flotte.
  static bool get canManageFleet {
    final r = (_userRole ?? '').toLowerCase();
    return r == 'superadmin' || r == 'admin';
  }

  /// E-mails pour lesquels on force le tableau de bord « maintenance » même si le backend renvoie `technician`.
  static const Set<String> _maintenanceDashboardEmails = {
    'lemjiddali341@gmail.com',
    'lemjiddall341@gmail.com',
  };

  /// Normalise l’e-mail et indique si la navigation doit aller vers [MaintenanceDashboardPage].
  static bool shouldOpenMaintenanceDashboard(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isNotEmpty && _maintenanceDashboardEmails.contains(e);
  }

  static Future<void> clearSavedTechnicianProfile() async {
    _savedTechnicianProfile = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTechnicianProfileJson);
  }

  /// Autorisé à ajouter des machines : rôle Concepteur uniquement.
  static bool get canAddMachineAsConcepteur {
    final r = (_userRole ?? '').toLowerCase();
    return r == 'concepteur' || r == 'conception';
  }

  static Future<void> loadSavedAuth() async {
    final p = await SharedPreferences.getInstance();
    _authToken = p.getString(_kToken);
    _userRole = p.getString(_kRole);
    _savedClientId = p.getString(_kClientId);
    _savedClientName = p.getString(_kClientName);
    _savedClientEmail = p.getString(_kClientEmail);
    _savedClientLocation = p.getString(_kClientLocation);
    _savedClientPhotoUrl = p.getString(_kClientPhotoUrl);
    _savedClientBackgroundUrl = p.getString(_kClientBackgroundUrl);
    final techRaw = p.getString(_kTechnicianProfileJson);
    if (techRaw != null && techRaw.isNotEmpty) {
      try {
        final d = json.decode(techRaw);
        if (d is Map<String, dynamic>) {
          _savedTechnicianProfile = d;
        }
      } catch (_) {
        _savedTechnicianProfile = null;
      }
    } else {
      _savedTechnicianProfile = null;
    }
    final concepteurRaw = p.getString(_kConcepteurProfileJson);
    if (concepteurRaw != null && concepteurRaw.isNotEmpty) {
      try {
        final d = json.decode(concepteurRaw);
        if (d is Map<String, dynamic>) {
          _savedConcepteurProfile = d;
        }
      } catch (_) {
        _savedConcepteurProfile = null;
      }
    } else {
      _savedConcepteurProfile = null;
    }
  }

  static Future<void> saveAuth(String? token, String role, {bool persist = true}) async {
    _authToken = (token != null && token.isNotEmpty) ? token : null;
    _userRole = role;
    final p = await SharedPreferences.getInstance();
    try {
      if (_authToken != null && persist) {
        await p.setString(_kToken, _authToken!);
      } else {
        await p.remove(_kToken);
      }

      if (persist) {
        await p.setString(_kRole, role);
      } else {
        await p.remove(_kRole);
      }
    } catch (e) {
      // Web : navigation privée / quota — le jeton reste en mémoire pour la session courante.
      debugPrint('ApiService.saveAuth: stockage local indisponible ($e)');
    }
  }


  static Future<void> clearAuth() async {
    _authToken = null;
    _userRole = null;
    _savedClientId = null;
    _savedClientName = null;
    _savedClientEmail = null;
    _savedClientLocation = null;
    _savedClientPhotoUrl = null;
    _savedClientBackgroundUrl = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kRole);
    await p.remove(_kClientId);
    await p.remove(_kClientName);
    await p.remove(_kClientEmail);
    await p.remove(_kClientLocation);
    await p.remove(_kClientPhotoUrl);
    await p.remove(_kClientBackgroundUrl);
    _savedTechnicianProfile = null;
    await p.remove(_kTechnicianProfileJson);
    _savedConcepteurProfile = null;
    await p.remove(_kConcepteurProfileJson);
  }

  /// À appeler après login concepteur : conserve nom/email/id pour le panneau profil.
  static Future<void> saveConcepteurSession(Map<String, dynamic> profile) async {
    final copy = Map<String, dynamic>.from(profile);
    copy.remove('loginPassword');
    copy.remove('password');
    copy.remove('token');
    _savedConcepteurProfile = copy;
    final p = await SharedPreferences.getInstance();
    try {
      await p.setString(_kConcepteurProfileJson, json.encode(copy));
    } catch (e) {
      debugPrint('ApiService.saveConcepteurSession: indisponible ($e)');
    }
  }

  /// À appeler après login technicien : permet au calendrier / profil de fonctionner après F5 sur le web.
  static Future<void> saveTechnicianSession(Map<String, dynamic> profile) async {
    final copy = Map<String, dynamic>.from(profile);
    copy.remove('loginPassword');
    copy.remove('password');
    copy.remove('token');
    _savedTechnicianProfile = copy;
    final p = await SharedPreferences.getInstance();
    try {
      await p.setString(_kTechnicianProfileJson, json.encode(copy));
    } catch (e) {
      debugPrint('ApiService.saveTechnicianSession: indisponible ($e)');
    }
  }

  static Future<void> saveClientSession({
    required String clientId,
    required String clientName,
    String clientEmail = '',
    String clientLocation = '',
    String? clientPhotoUrl,
    String? clientBackgroundUrl,
  }) async {
    _savedClientId = clientId.trim();
    _savedClientName = clientName.trim();
    _savedClientEmail = clientEmail.trim();
    _savedClientLocation = clientLocation.trim();
    if (clientPhotoUrl != null) {
      _savedClientPhotoUrl = clientPhotoUrl.trim();
    }
    if (clientBackgroundUrl != null) {
      _savedClientBackgroundUrl = clientBackgroundUrl.trim();
    }

    final p = await SharedPreferences.getInstance();
    if (_savedClientId != null && _savedClientId!.isNotEmpty) {
      await p.setString(_kClientId, _savedClientId!);
    } else {
      await p.remove(_kClientId);
    }
    if (_savedClientName != null && _savedClientName!.isNotEmpty) {
      await p.setString(_kClientName, _savedClientName!);
    } else {
      await p.remove(_kClientName);
    }
    if (_savedClientEmail != null && _savedClientEmail!.isNotEmpty) {
      await p.setString(_kClientEmail, _savedClientEmail!);
    } else {
      await p.remove(_kClientEmail);
    }
    if (_savedClientLocation != null && _savedClientLocation!.isNotEmpty) {
      await p.setString(_kClientLocation, _savedClientLocation!);
    } else {
      await p.remove(_kClientLocation);
    }
    if (_savedClientPhotoUrl != null && _savedClientPhotoUrl!.isNotEmpty) {
      await p.setString(_kClientPhotoUrl, _savedClientPhotoUrl!);
    } else {
      await p.remove(_kClientPhotoUrl);
    }
    if (_savedClientBackgroundUrl != null &&
        _savedClientBackgroundUrl!.isNotEmpty) {
      await p.setString(_kClientBackgroundUrl, _savedClientBackgroundUrl!);
    } else {
      await p.remove(_kClientBackgroundUrl);
    }
  }

  /// Efface la session client persistée (sans toucher au jeton ni au rôle).
  /// Utile après connexion Google en tant que technicien ou maintenance.
  static Future<void> clearStoredClientSession() async {
    _savedClientId = null;
    _savedClientName = null;
    _savedClientEmail = null;
    _savedClientLocation = null;
    _savedClientPhotoUrl = null;
    _savedClientBackgroundUrl = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kClientId);
    await p.remove(_kClientName);
    await p.remove(_kClientEmail);
    await p.remove(_kClientLocation);
    await p.remove(_kClientPhotoUrl);
    await p.remove(_kClientBackgroundUrl);
  }

  /// Profil minimal technicien depuis les query params OAuth web (`machineIds` = IDs séparés par des virgules).
  static Map<String, dynamic> technicianProfileFromOAuthParams(
    Map<String, String> qp,
  ) {
    final raw = (qp['machineIds'] ?? '').trim();
    final mids =
        raw.isEmpty
            ? <String>[]
            : raw
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
    return {
      'technicianId': (qp['technicianId'] ?? '').trim(),
      'id': (qp['id'] ?? qp['technicianId'] ?? '').trim(),
      '_id': (qp['_id'] ?? '').trim(),
      'name': (qp['name'] ?? '').trim(),
      'email': (qp['email'] ?? '').trim(),
      'companyId': (qp['companyId'] ?? '').trim(),
      'machineIds': mids,
      'imageUrl': (qp['imageUrl'] ?? '').trim(),
      'specialization': (qp['specialization'] ?? '').trim(),
      'status': (qp['status'] ?? '').trim(),
    };
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
        'Session non connectée : reconnectez-vous depuis l’écran de connexion.',
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
      // Toujours localhost côté web : même résolution IPv4 que node server.js.
      return 'http://localhost:$apiPort/api';
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
      var message =
          map['error']?.toString() ?? map['message']?.toString();
      if (message != null && message.trim().isNotEmpty) {
        if (response.statusCode == 404) {
          final p = map['path']?.toString();
          if (p != null && p.trim().isNotEmpty) {
            message = '${message.trim()} — $p';
          }
          final h = map['hint']?.toString();
          if (h != null && h.trim().isNotEmpty) {
            message = '${message.trim()}. $h';
          }
        }
        throw Exception(message.trim());
      }
    }
    throw Exception('$fallbackMessage (${response.statusCode})');
  }

  // --- Technicians ---
  
  static Future<List<Map<String, dynamic>>> getTechnicians() async {
    final response = await http.get(
      Uri.parse('$baseUrl/technicians'),
      headers: await jsonHeadersAuthorized(),
    );
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
    final response = await http.get(
      Uri.parse('$baseUrl/clients/$clientId/technicians'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Erreur de chargement des techniciens du client');
    }
  }

  static Map<String, String> get _noCacheHeaders => const {
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
  };

  /// Sur le web, éviter Cache-Control/Pragma en requête (preflight CORS bloqué sinon).
  static Map<String, String> get _getHeaders =>
      kIsWeb ? const {} : _noCacheHeaders;

  /// Réessaie les GET catalogue si le backend n’est pas encore prêt (Failed to fetch / 503).
  static Future<http.Response> _getWithStartupRetry(
    Uri uri, {
    int maxAttempts = 4,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await http
            .get(uri, headers: _getHeaders)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 503 && attempt < maxAttempts - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: 450 * (attempt + 1)),
          );
          continue;
        }
        return response;
      } on http.ClientException catch (e) {
        lastError = e;
        debugPrint(
          'API GET ${uri.path} tentative ${attempt + 1}/$maxAttempts: $e',
        );
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint(
          'API GET ${uri.path} timeout tentative ${attempt + 1}/$maxAttempts',
        );
      }
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(
          Duration(milliseconds: 450 * (attempt + 1)),
        );
      }
    }
    throw lastError ??
        Exception(
          'Impossible de joindre le serveur API (${uri.origin}). '
          'Vérifiez que node server.js tourne sur le port attendu.',
        );
  }

  /// Machines assignées (companyId renseigné) — base Atlas via API.
  static Future<List<Map<String, dynamic>>> getMachines({String? concepterId}) async {
    var url = '$baseUrl/machines';
    if (concepterId != null && concepterId.isNotEmpty) {
      url += '?concepterId=${Uri.encodeComponent(concepterId)}';
    }
    final response = await http.get(
      Uri.parse(url),
      headers: _getHeaders,
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Erreur de chargement des machines');
  }


  /// URIs catalogue : repli localhost ↔ 127.0.0.1 si [API_BASE] force un seul hôte.
  static List<Uri> _catalogMachinesUris({
    String? concepterId,
    bool includeAll = false,
  }) {
    var path = '$baseUrl/machines?catalog=1';
    if (includeAll) {
      path += '&includeAllMongo=1';
    }
    if (concepterId != null && concepterId.isNotEmpty) {
      path += '&concepterId=${Uri.encodeComponent(concepterId)}';
    }
    final primary = Uri.parse(path);
    if (!kIsWeb) return [primary];
    const fromEnv = String.fromEnvironment('API_BASE', defaultValue: '');
    if (fromEnv.isNotEmpty) return [primary];
    final altHost =
        primary.host == '127.0.0.1' ? 'localhost' : '127.0.0.1';
    if (altHost == primary.host) return [primary];
    return [primary, primary.replace(host: altHost)];
  }

  /// Catalogue / liste complète : uniquement la base principale (Atlas), pas de repli local.
  static Future<List<Map<String, dynamic>>> getCatalogMachines({
    String? concepterId,
    bool includeAll = false,
  }) async {
    Object? lastError;
    for (final uri in _catalogMachinesUris(
      concepterId: concepterId,
      includeAll: includeAll,
    )) {
      try {
        debugPrint('[API] GET catalogue → $uri');
        final response = await _getWithStartupRetry(uri);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          return data.cast<Map<String, dynamic>>();
        }
        if (response.statusCode == 503) {
          _throwApiError(
            response,
            'Base de données indisponible — vérifiez MONGO_URI et redémarrez node server.js',
          );
        }
        _throwApiError(response, 'Erreur de chargement du catalogue machines');
      } catch (e) {
        lastError = e;
        debugPrint('[API] échec catalogue $uri → $e');
      }
    }
    throw lastError ??
        Exception(
          'Impossible de joindre l’API (${baseUrl}). '
          'Démarrez iot-backend : node server.js (port 3001).',
        );
  }

  /// Alias historique → [getCatalogMachines] (source unique Atlas).
  static Future<List<Map<String, dynamic>>> getAllMachinesFromMongo() =>
      getCatalogMachines();

  /// Catalogue accueil / client : une seule requête API, pas de données locales ni fallback.
  static Future<List<Map<String, dynamic>>> getMachinesForHomeCatalog() =>
      getCatalogMachines();

  static Future<List<Map<String, dynamic>>> getUnassignedMachines() async {
    final response = await http.get(
      Uri.parse('$baseUrl/machines?unassigned=1'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Erreur de chargement des machines non assignées');
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

  static Future<Map<String, dynamic>> updateMyTechnicianProfile(Map<String, dynamic> data) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/technician/me'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      _throwApiError(response, 'Erreur lors de la modification du profil technicien');
    }
  }

  /// Profil Mongo du technicien connecté (`imageUrl`, `name`, …) — GET /api/technician/me.
  static Future<Map<String, dynamic>> getMyTechnicianProfile() async {
    final response = await http.get(
      Uri.parse('$baseUrl/technician/me'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    _throwApiError(response, 'Profil technicien indisponible');
  }

  /// Machines Mongo liées au technicien connecté (`machineIds`) — GET /api/technician/me/machines.
  static Future<List<Map<String, dynamic>>> getMyTechnicianMachines() async {
    final response = await http.get(
      Uri.parse('$baseUrl/technician/me/machines'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Chargement des machines technicien impossible');
  }

  /// Machines assignées à un technicien (super-admin / admin client / conception).
  static Future<List<Map<String, dynamic>>> getTechnicianMachinesByTechnicianId(String technicianId) async {
    final enc = Uri.encodeComponent(technicianId.trim());
    final response = await http.get(
      Uri.parse('$baseUrl/technicians/$enc/machines'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Chargement machines du technicien impossible');
  }

  /// Pour [Image.network] vers fichiers sur la même origine que [baseUrl] (Authorization requise).
  static Map<String, String>? bearerHeadersForNetworkImage() {
    final t = authToken;
    if (t == null || t.isEmpty) return null;
    return {'Authorization': 'Bearer $t'};
  }

  static Future<void> deleteTechnician(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/technicians/$id'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Suppression du technicien impossible');
  }

  /// Profil du concepteur connecté — GET /api/concepteurs/me.
  static Future<Map<String, dynamic>> getMyConcepteurProfile() async {
    final response = await http.get(
      Uri.parse('$baseUrl/concepteurs/me'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    _throwApiError(response, 'Profil concepteur indisponible');
  }

  /// Mise à jour du profil concepteur connecté — PATCH /api/concepteurs/me.
  static Future<Map<String, dynamic>> updateMyConcepteurProfile(
    Map<String, dynamic> data,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/concepteurs/me'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    _throwApiError(response, 'Mise à jour du profil concepteur refusée');
  }

  // -------------------------
  // CLIENTS
  // -------------------------

  /// Comptages KPI dashboard admin (MongoDB).
  static Future<Map<String, int>> getDashboardKpis() async {
    final response = await http.get(
      Uri.parse('$baseUrl/dashboard/kpis'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      int n(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      return {
        'clients': n(data['clients']),
        'machines': n(data['machines']),
        'machinesEnLigne': n(data['machinesEnLigne']),
        'concepteurs': n(data['concepteurs']),
        'technicians': n(data['technicians']),
        'documents': n(data['documents']),
      };
    }
    _throwApiError(response, 'Erreur chargement KPI dashboard');
  }

  /// Risques (télémétrie) + marqueurs carte pour machines en marche.
  static Future<Map<String, dynamic>> getDashboardFleetOverview() async {
    final response = await http.get(
      Uri.parse('$baseUrl/dashboard/fleet-overview'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Erreur chargement synthèse flotte');
  }

  static Future<List<Map<String, dynamic>>> getClients() async {
    final response = await http.get(
      Uri.parse('$baseUrl/clients'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      List<dynamic> body = json.decode(response.body);
      return body.map((dynamic item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Erreur lors du chargement des clients: ${response.statusCode}');
    }
  }

  /// Rapport pour super-admin / admin / conception : email, mot de passe défini, blocage, collisions d’identité.
  static Future<Map<String, dynamic>> getClientLoginSurvey() async {
    final response = await http.get(
      Uri.parse('$baseUrl/clients/login-survey'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Chargement du rapport connexions clients impossible');
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

  static Future<void> sendClientSignupCode({
    required String email,
    String? name,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/client-signup/send-code'),
      headers: _jsonHeaders(),
      body: json.encode({
        'email': email.trim().toLowerCase(),
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Envoi du code par email impossible');
  }

  static Future<Map<String, dynamic>> clientSelfRegister(
    Map<String, dynamic> data,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/client-self-register'),
      headers: _jsonHeaders(),
      body: json.encode(data),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Creation de compte client impossible');
  }

  /// Vérifie si le backend a de vrais identifiants Google OAuth (évite invalid_client).
  static Future<bool> isGoogleOAuthConfigured() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/auth/google/status'),
            headers: _getHeaders,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return false;
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded['configured'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> clientGoogleAuth({
    required String idToken,
    String location = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/client-google-auth'),
      headers: _jsonHeaders(),
      body: json.encode({
        'idToken': idToken.trim(),
        if (location.trim().isNotEmpty) 'location': location.trim(),
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Connexion Google client impossible');
  }

  static Future<Map<String, dynamic>> createPurchaseRequest(
    Map<String, dynamic> data,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/purchase-requests'),
      headers: _jsonHeaders(),
      body: json.encode(data),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Creation de la demande d\'achat refusee');
  }

  static Future<List<Map<String, dynamic>>> getPurchaseRequests({
    String? status,
  }) async {
    final uri = Uri.parse('$baseUrl/purchase-requests').replace(
      queryParameters:
          (status != null && status.trim().isNotEmpty)
              ? {'status': status.trim().toUpperCase()}
              : null,
    );
    final response = await http.get(
      uri,
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Chargement des demandes d\'achat impossible');
  }

  static Future<void> updatePurchaseRequestStatus(
    String id,
    String status, {
    String reviewedByName = '',
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/purchase-requests/$id/status'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({
        'status': status.toUpperCase(),
        if (reviewedByName.trim().isNotEmpty)
          'reviewedByName': reviewedByName.trim(),
      }),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Mise a jour demande achat impossible');
  }

  static Future<Map<String, dynamic>> provisionPurchaseRequestTeam(
    String purchaseRequestId,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/purchase-requests/$purchaseRequestId/provision-team'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Provision equipe impossible');
  }

  static Future<Map<String, dynamic>> addMachineToClient(String clientId, Map<String, dynamic> data) async {
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

  static Future<Map<String, dynamic>> createStandaloneMachine(
    Map<String, dynamic> data, {
    String actorRole = '',
    String? concepterId,
  }) async {
    final routeRole = actorRole.toLowerCase().trim();
    final roleAllowed = routeRole == 'concepteur' || routeRole == 'conception';
    if (!roleAllowed && !canAddMachineAsConcepteur) {
      throw Exception('Accès refusé : seul le rôle Concepteur peut ajouter une machine.');
    }
    
    final body = Map<String, dynamic>.from(data);
    if (concepterId != null && concepterId.isNotEmpty) {
      body['concepteurId'] = concepterId;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/machines'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(body),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      _throwApiError(response, 'Creation machine refusee');
    }
  }

  static Future<Map<String, dynamic>> assignMachineToClient(String machineId, String clientId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/machines/$machineId/assign-client'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({'clientId': clientId}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> getMachinesForClient(String clientId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clients/$clientId/machines'),
      headers: await jsonHeadersAuthorized(),
    );
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
      final response = await http.get(
        Uri.parse('$baseUrl/companies'),
        headers: await jsonHeadersAuthorized(),
      );
      if (response.statusCode == 200) {
        List<dynamic> body = json.decode(response.body);
        return body.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (_) {}
    return await getClients();
  }

  // -------------------------
  // AUTH
  // -------------------------

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final emailNorm = email.trim().toLowerCase();
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': emailNorm, 'password': password}),
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

  /// Profil Mongo de l’agent maintenance connecté — PATCH `/maintenance/me`.
  static Future<Map<String, dynamic>> updateMyMaintenanceProfile(
    Map<String, dynamic> data,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/maintenance/me'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    _throwApiError(response, 'Mise à jour du profil maintenance refusée');
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
    final response = await http.get(
      Uri.parse('$baseUrl/model-metrics'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  // -------------------------
  // REMOTE MACHINE CONTROL
  // -------------------------

  // addMachine(Map data) was a duplicate of createStandaloneMachine, removed.

  static Future<Map<String, dynamic>> getMachineInfo(String machineId) async {
    final response = await http.get(Uri.parse('$baseUrl/machines/$machineId'));
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
    _throwApiError(response, 'Arrêt machine impossible');
  }

  static Future<Map<String, dynamic>> startMachine(String machineId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/machines/$machineId/start'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Démarrage machine impossible');
  }

  static Future<Map<String, dynamic>> startMachineMarche(String machineId) => startMachine(machineId);

  static Future<void> deleteMachine(String machineId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/machines/$machineId'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      _throwApiError(response, 'Impossible de supprimer la machine');
    }
  }

  static String fullUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    if (path.startsWith('data:')) return path; // Base64
    // Assumes backend serves uploads from /uploads or similar
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$baseUrl/$cleanPath'.replaceFirst('/api/', '/'); 
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

  static Future<List<Map<String, dynamic>>> getMaintenanceOrders({String? machineId}) async {
    final qp = <String, String>{
      if (machineId != null && machineId.trim().isNotEmpty)
        'machineId': machineId.trim(),
    };
    final uri = Uri.parse('$baseUrl/maintenance-orders').replace(
      queryParameters: qp.isEmpty ? null : qp,
    );
    final response = await http.get(
      uri,
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

  /// Réponse serveur : `{ ok, noteId, note? }` — `note` permet d’afficher la mission sans attendre le websocket.
  static Future<Map<String, dynamic>> addCoordinationNote(
    String interventionId,
    String content, {
    String? authorName,
    bool isMission = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/coordination'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({
        'content': content,
        'isMission': isMission,
        if (authorName != null && authorName.isNotEmpty) 'authorName': authorName,
      }),
    );
    if (response.statusCode == 200) {
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded as Map);
        }
      } catch (_) {}
      return {'ok': true};
    }
    _throwApiError(response, 'Envoi note de coordination refusé');
  }

  static Future<void> updateMissionStatus(
    String interventionId,
    String noteId,
    String status, // SENT, CONFIRMED, COMPLETED
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/coordination/$noteId/status'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({'status': status}),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Mise à jour du statut mission refusée');
  }

  /// Accusé sur un message du canal discussion (`messages[]`), pas une note de coordination.
  static Future<void> updateDiagnosticMessageStatus(
    String interventionId,
    String messageId,
    String status,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/diagnostic-interventions/$interventionId/messages/$messageId/status'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({'status': status}),
    );
    if (response.statusCode == 200) return;
    _throwApiError(response, 'Mise à jour du statut du message refusée');
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

  static Future<List<Map<String, dynamic>>> getInterventionArchives({
    String? machineId,
    String? companyId,
    String? interventionId,
  }) async {
    final qp = <String, String>{
      if (machineId != null && machineId.trim().isNotEmpty)
        'machineId': machineId.trim(),
      if (companyId != null && companyId.trim().isNotEmpty)
        'companyId': companyId.trim(),
      if (interventionId != null && interventionId.trim().isNotEmpty)
        'interventionId': interventionId.trim(),
    };
    final uri = Uri.parse('$baseUrl/intervention-archives').replace(
      queryParameters: qp.isEmpty ? null : qp,
    );
    final response = await http.get(
      uri,
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Chargement des archives de pannes impossible');
  }

  static Future<Map<String, dynamic>> exportInterventionArchive(
    String interventionId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/intervention-archives/$interventionId/export'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final dynamic decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'raw': decoded};
    }
    _throwApiError(response, 'Export archive impossible');
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
    int limit = 300,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/messages/${Uri.encodeComponent(roomId)}?limit=$limit'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return <Map<String, dynamic>>[];
  }

  static Future<List<Map<String, dynamic>>> getTechnicianConversations(
    String technicianId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/conversations/conception'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return <Map<String, dynamic>>[];
  }

  static Future<List<Map<String, dynamic>>> getClientConversations(
    String clientId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/conversations/conception'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return <Map<String, dynamic>>[];
  }

  static Future<List<Map<String, dynamic>>> getConceptionConversations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/conversations/conception'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return <Map<String, dynamic>>[];
  }

  static Future<List<Map<String, dynamic>>> searchConcepteurs(String query) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/concepteurs/search?query=${Uri.encodeComponent(query)}'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return <Map<String, dynamic>>[];
  }

  static Future<void> deleteChatRoom(String roomId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/chat/rooms/${Uri.encodeComponent(roomId)}'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      _throwApiError(response, 'Impossible de supprimer la discussion');
    }
  }

  static Future<void> deleteChatMessage(String messageId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/chat/messages/$messageId'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      _throwApiError(response, 'Impossible de supprimer le message');
    }
  }

  static Future<String?> uploadFile({
    required String base64Data,
    required String filename,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/upload'),
        headers: await jsonHeadersAuthorized(),
        body: json.encode({
          'base64Data': base64Data,
          'filename': filename,
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['url'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Erreur uploadFile: $e');
      return null;
    }
  }

  // Alias for backward compatibility
  static Future<String?> uploadChatAttachment({
    required String base64Data,
    required String filename,
  }) => uploadFile(base64Data: base64Data, filename: filename);

  // -------------------------
  // CONTROLES (STEP 4 & 5)
  // -------------------------

  static Future<List<Map<String, dynamic>>> getControles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/controles'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Erreur de chargement des contrôles');
  }

  static Future<List<Map<String, dynamic>>> getAllControles({
    int days = 60,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/controles?days=$days'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Erreur de chargement du calendrier des contrôles');
  }

  /// Contrôles rattachés à une machine (préventifs, statuts, dates prévues).
  static Future<List<Map<String, dynamic>>> getControlesForMachine(String machineId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/controles/machine/${Uri.encodeComponent(machineId)}'),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Erreur de chargement des contrôles machine');
  }

  static Future<List<Map<String, dynamic>>> getControlesForTechnician(
    String technicianId, {
    int days = 30,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/controles/technicien/${Uri.encodeComponent(technicianId)}?days=$days',
      ),
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final dynamic data = json.decode(response.body);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      if (data is Map<String, dynamic>) {
        final list = data['controles'] ?? data['machines'] ?? data['data'] ?? [];
        if (list is List) {
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
      return <Map<String, dynamic>>[];
    }
    _throwApiError(response, 'Erreur de chargement des contrôles technicien');
  }

  /// Compte-rendu libre depuis le calendrier technicien (jour + machine). Crée ou clôt une fiche.
  static Future<Map<String, dynamic>> submitControleCalendrierSaisie({
    required String machineId,
    required String jourYyyyMmDd,
    required String compteRendu,
    String? technicienId,
    String? technicienNom,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/controles/terrain'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({
        'machineId': machineId,
        'jour': jourYyyyMmDd,
        'compteRendu': compteRendu,
        if (technicienId != null && technicienId.isNotEmpty) 'technicienId': technicienId,
        if (technicienNom != null && technicienNom.isNotEmpty) 'technicienNom': technicienNom,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = json.decode(response.body);
      if (decoded is! Map) {
        throw Exception('Réponse serveur invalide (attendu un objet JSON)');
      }
      return Map<String, dynamic>.from(decoded);
    }
    _throwApiError(response, 'Erreur enregistrement du compte-rendu');
  }

  /// Entrées `control_calendrier` pour une machine (journal du bouton Valider).
  static Future<List<Map<String, dynamic>>> getControlCalendrierJournal(
    String machineId, {
    int limit = 50,
  }) async {
    final uri = Uri.parse('$baseUrl/controles/calendrier-journal').replace(
      queryParameters: <String, String>{
        'machineId': machineId,
        'limit': '$limit',
      },
    );
    final response = await http.get(uri, headers: await jsonHeadersAuthorized());
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return <Map<String, dynamic>>[];
    }
    _throwApiError(response, 'Erreur chargement journal calendrier');
  }

  static Future<void> updateControleStatus(
    String id,
    String status, {
    String? notes,
    String? technicienId,
    Map<String, dynamic>? extraPayload,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/controles/$id/statut'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({
        'statut': status,
        if (notes != null) 'notes': notes,
        if (technicienId != null && technicienId.isNotEmpty) 'technicienId': technicienId,
        ...?extraPayload,
      }),
    );
    if (response.statusCode != 200) {
      _throwApiError(response, 'Erreur mise à jour statut contrôle');
    }
  }

  static Future<Map<String, dynamic>> assignControleToTechnician(
    String controleId, {
    required String technicienId,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/controles/$controleId/assign'),
      headers: await jsonHeadersAuthorized(),
      body: json.encode({
        'technicienId': technicienId,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _throwApiError(response, 'Affectation technicien impossible');
  }

  static Future<List<Map<String, dynamic>>> getPreventiveHistory({
    String? machineId,
    String? technicienId,
  }) async {
    final qp = <String, String>{
      if (machineId != null && machineId.trim().isNotEmpty) 'machineId': machineId.trim(),
      if (technicienId != null && technicienId.trim().isNotEmpty) 'technicienId': technicienId.trim(),
    };
    final uri = Uri.parse('$baseUrl/controles/preventive-history').replace(
      queryParameters: qp.isEmpty ? null : qp,
    );
    final response = await http.get(
      uri,
      headers: await jsonHeadersAuthorized(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    _throwApiError(response, 'Chargement historique maintenance préventive impossible');
  }

}
