import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'services/api_service.dart';
import 'services/global_notification_service.dart';
import 'dashboard_page.dart';
import 'client_dashboard_page.dart';
import 'add_client_page.dart';
import 'technician_profile_page.dart';
import 'add_technician_page.dart';
import 'machine_team_page.dart';
import 'machine_detail_ai_page.dart';
import 'message_equipe_page.dart';
import 'conception_observatory_page.dart';
import 'maintenance_login_page.dart';
import 'maintenance_dashboard_page.dart';
import 'maintenance_profile_page.dart';
import 'maintenance_machine_hub_page.dart';
import 'technician_terminal_page.dart';
import 'technician_collaboration_page.dart';
import 'mission_control_page.dart';
import 'control_calendar_page.dart';
import 'control_reports_history_page.dart';
import 'preventive_history_page.dart';
import 'concepteur_dashboard_page.dart';
import 'technician_dashboard_page.dart';
import 'machine_consultation_page.dart';

final GlobalKey<NavigatorState> globalNavigatorKey = _rootNavigatorKey;
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

const Set<String> _appRouteNames = {
  '/',
  '/machines',
  '/login',
  '/dashboard',
  '/client-dashboard',
  '/add-client',
  '/team',
  '/technician-profile',
  '/technician-terminal',
  '/technician-collaboration',
  '/conception-observatory',
  '/concepteur-dashboard',
  '/mission-control',
  '/control-calendar',
  '/control-reports-history',
  '/preventive-history',
  '/maintenance-login',
  '/maintenance-dashboard',
  '/maintenance-profile',
  '/maintenance-machine-hub',
  '/add-technician',
  '/machine-team',
  '/machine-detail',
  '/message-equipe',
  '/technician-dashboard',
  '/machine-consultation',
};

/// Sur le web, conserve la route après F5 (ex. `/#/dashboard` → `/dashboard`).
String resolveInitialWebRoute() {
  if (!kIsWeb) return '/';
  final frag = Uri.base.fragment.trim();
  if (frag.isNotEmpty) {
    final path = frag.split('?').first;
    if (path.startsWith('/') && _appRouteNames.contains(path)) return path;
    final withSlash = path.startsWith('/') ? path : '/$path';
    if (_appRouteNames.contains(withSlash)) return withSlash;
  }
  final path = Uri.base.path;
  if (path.isNotEmpty && path != '/' && _appRouteNames.contains(path)) {
    return path;
  }
  return '/';
}

/// Point d’entrée : toujours [LoginPage] d’abord, puis redirection vers `/conception-observatory`
/// si session **concepteur** sauvegardée — évite l’erreur web `RenderBox was not laid out` / focus
/// quand l’Observatory était la racine directe du [MaterialApp].
class SessionEntry extends StatefulWidget {
  final String? initialSection;
  const SessionEntry({super.key, this.initialSection});

  @override
  State<SessionEntry> createState() => _SessionEntryState();
}

class _SessionEntryState extends State<SessionEntry> {
  bool _redirectScheduled = false;

  @override
  void initState() {
    super.initState();
    _consumeGoogleOAuthReturnFromAnyWebRoute();
  }

  Future<void> _consumeGoogleOAuthReturnFromAnyWebRoute() async {
    if (!kIsWeb || _redirectScheduled) return;
    final qp = _readMergedWebQueryParams();
    if (qp['googleAuth'] == null) return;
    if (qp['googleAuth'] != '1') {
      final msg = (qp['error'] ?? 'Connexion Google refusée').trim();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      });
      return;
    }

    final token = (qp['token'] ?? '').trim();
    var role = (qp['role'] ?? 'client').trim().toLowerCase();
    if (role == 'super_admin') role = 'superadmin';
    if (role == 'company_admin') role = 'admin';
    final oauthEmail = (qp['email'] ?? '').trim();
    if (ApiService.shouldOpenMaintenanceDashboard(oauthEmail)) {
      role = 'maintenance';
    } else if (ApiService.shouldOpenConcepteurDashboard(oauthEmail)) {
      role = 'concepteur';
    }
    if (token.isEmpty) return;

    await ApiService.saveAuth(token, role);

    if (role == 'technician') {
      final profile = ApiService.technicianProfileFromOAuthParams(qp);
      await ApiService.clearStoredClientSession();
      await ApiService.saveTechnicianSession(profile);
    } else if (role == 'maintenance' ||
        role == 'conception' ||
        role == 'concepteur' ||
        role == 'superadmin' ||
        role == 'admin') {
      await ApiService.clearStoredClientSession();
      if (role == 'maintenance') {
        await ApiService.clearSavedTechnicianProfile();
      }
    } else {
      await ApiService.saveClientSession(
        clientId: (qp['clientId'] ?? '').trim(),
        clientName: (qp['name'] ?? 'Client').trim(),
        clientEmail: (qp['email'] ?? '').trim(),
        clientLocation: (qp['location'] ?? '').trim(),
        clientPhotoUrl:
            (qp['photoUrl'] ??
                    qp['avatarUrl'] ??
                    qp['profilePhotoUrl'] ??
                    qp['imageUrl'] ??
                    qp['image'] ??
                    '')
                .trim(),
      );
    }

    if (!mounted) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (role == 'technician') {
        final profile = ApiService.technicianProfileFromOAuthParams(qp);
        Navigator.of(context).pushReplacementNamed(
          '/technician-profile',
          arguments: profile,
        );
        return;
      }
      if (role == 'maintenance') {
        Navigator.of(context).pushReplacementNamed('/maintenance-dashboard');
        return;
      }
      if (role == 'conception' || role == 'concepteur') {
        Navigator.of(context).pushReplacementNamed('/concepteur-dashboard');
        return;
      }
      if (role == 'superadmin' || role == 'admin') {
        Navigator.of(context).pushReplacementNamed('/dashboard');
        return;
      }
      Navigator.of(context).pushReplacementNamed('/client-dashboard');
    });
  }

  Map<String, String> _readMergedWebQueryParams() {
    final params = <String, String>{...Uri.base.queryParameters};
    final frag = Uri.base.fragment;
    if (frag.contains('?')) {
      final fragQuery = frag.split('?').skip(1).join('?');
      params.addAll(Uri.splitQueryString(fragQuery));
    }
    return params;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_redirectScheduled) return;
    final role = (ApiService.savedUserRole ?? '').toLowerCase();
    final token = ApiService.authToken ?? '';
    if (token.isEmpty) return;
    if (role == 'conception' || role == 'concepteur') {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/concepteur-dashboard');
      });
      return;
    }
    if (role == 'maintenance') {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/maintenance-dashboard');
      });
      return;
    }
    if (role == 'technician') {
      final tp = ApiService.savedTechnicianProfile;
      final techEmail = (tp?['email'] ?? '').toString().trim();
      if (ApiService.shouldOpenMaintenanceDashboard(techEmail)) {
        _redirectScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final t = ApiService.authToken;
          await ApiService.saveAuth(t, 'maintenance');
          await ApiService.clearSavedTechnicianProfile();
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed('/maintenance-dashboard');
        });
        return;
      }
      if (tp != null && tp.isNotEmpty) {
        _redirectScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed(
            '/technician-profile',
            arguments: Map<String, dynamic>.from(tp),
          );
        });
        return;
      }
    }
    if (role == 'client' &&
        (ApiService.savedClientId ?? '').trim().isNotEmpty) {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/client-dashboard');
      });
      return;
    }
    if (role == 'superadmin' || role == 'admin') {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/dashboard');
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) => HomePage(initialSection: widget.initialSection);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('fr_FR');
  } catch (e, st) {
    debugPrint('initializeDateFormatting(fr_FR): $e\n$st');
  }
  try {
    await ApiService.loadSavedAuth();
    GlobalNotificationService().init();
  } catch (e, st) {
    debugPrint('ApiService.loadSavedAuth: $e\n$st');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _rootNavigatorKey,
      title: 'Predictive Cloud',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFFF6E00),
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6E00),
          surface: Color(0xFF0F0F1E),
          onSurface: Color(0xFFF4F4F9),
          surfaceContainerHighest: Color(0xFF1E1E2E),
        ),
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ).apply(
          bodyColor: const Color(0xFFF4F4F9),
          displayColor: const Color(0xFFF4F4F9),
        ),
      ),
      initialRoute: resolveInitialWebRoute(),
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (child != null) Positioned.fill(child: child),
          ],
        );
      },
      routes: {
        '/': (context) => const SessionEntry(),
        '/machines': (context) => const SessionEntry(initialSection: 'catalog'),
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => const DashboardPage(),
        '/client-dashboard':
            (context) => ClientDashboardPage(
              clientName:
                  (ApiService.savedClientName ?? 'Espace client').trim(),
              clientId: (ApiService.savedClientId ?? '').trim(),
              clientData: {
                'clientId': (ApiService.savedClientId ?? '').trim(),
                'id': (ApiService.savedClientId ?? '').trim(),
                'name': (ApiService.savedClientName ?? 'Espace client').trim(),
                'email': (ApiService.savedClientEmail ?? '').trim(),
                'location': (ApiService.savedClientLocation ?? '').trim(),
              },
            ),

        '/add-client': (context) => const AddClientPage(),
        '/team': (context) => const DashboardPage(),
        '/technician-profile': (context) => const TechnicianProfilePage(),
        '/technician-terminal': (context) => const TechnicianTerminalPage(),
        '/technician-collaboration':
            (context) => const TechnicianCollaborationPage(),
        '/conception-observatory':
            (context) => const ConceptionObservatoryPage(),
        '/concepteur-dashboard': (context) => const ConcepteurDashboardPage(),
        '/mission-control': (context) => const MissionControlPage(),
        '/control-calendar': (context) => const ControlCalendarPage(),
        '/control-reports-history':
            (context) => const ControlReportsHistoryPage(),
        '/preventive-history': (context) => const PreventiveHistoryPage(),

        '/maintenance-login': (context) => const MaintenanceLoginPage(),
        '/maintenance-dashboard': (context) => const MaintenanceDashboardPage(),
        '/maintenance-profile': (context) => const MaintenanceProfilePage(),
        '/maintenance-machine-hub': (context) => const MaintenanceMachineHubPage(),
        '/add-technician': (context) => const AddTechnicianPage(),
        '/machine-team': (context) => const MachineTeamPage(),
        '/machine-detail':
            (context) => const MachineDetailAiPage(machineId: 'MAC_HATHA'),
        '/message-equipe': (context) => const MessageEquipePage(),
        '/technician-dashboard': (context) => const TechnicianDashboardPage(),
        '/machine-consultation': (context) => const MachineConsultationPage(),
      },
    );
  }
}

