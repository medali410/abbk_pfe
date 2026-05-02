import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'services/api_service.dart';
import 'dashboard_page.dart';
import 'client_dashboard_page.dart';
import 'add_client_page.dart';
import 'project_team_page.dart';
import 'technician_profile_page.dart';
import 'add_technician_page.dart';
import 'machine_team_page.dart';
import 'machine_detail_ai_page.dart';
import 'message_equipe_page.dart';
import 'conception_observatory_page.dart';
import 'maintenance_login_page.dart';
import 'maintenance_dashboard_page.dart';
import 'technician_terminal_page.dart';
import 'technician_collaboration_page.dart';
import 'mission_control_page.dart';
import 'control_calendar_page.dart';
import 'control_reports_history_page.dart';
import 'preventive_history_page.dart';
import 'concepteur_dashboard_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Point d’entrée : toujours [LoginPage] d’abord, puis redirection vers `/conception-observatory`
/// si session **concepteur** sauvegardée — évite l’erreur web `RenderBox was not laid out` / focus
/// quand l’Observatory était la racine directe du [MaterialApp].
class SessionEntry extends StatefulWidget {
  const SessionEntry({super.key});

  @override
  State<SessionEntry> createState() => _SessionEntryState();
}

class _SessionEntryState extends State<SessionEntry> {
  bool _redirectScheduled = false;

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
  }

  @override
  Widget build(BuildContext context) => const HomePage();
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
      initialRoute: '/',
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (child != null) Positioned.fill(child: child),
            if (kDebugMode) const _ApiBaseDebugBadge(),
            if (kIsWeb) const _GlobalBackButtonOverlay(),
          ],
        );
      },
      routes: {
        '/': (context) => const SessionEntry(),
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
        '/team': (context) => const ProjectTeamPage(),
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
        '/add-technician': (context) => const AddTechnicianPage(),
        '/machine-team': (context) => const MachineTeamPage(),
        '/machine-detail':
            (context) => const MachineDetailAiPage(machineId: 'MAC_HATHA'),
        '/message-equipe': (context) => const MessageEquipePage(),
      },
    );
  }
}

class _GlobalBackButtonOverlay extends StatelessWidget {
  const _GlobalBackButtonOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 10, top: 6),
          child: Material(
            color: const Color(0xFFF0D9B5),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                final nav = _rootNavigatorKey.currentState;
                if (nav == null) return;
                if (nav.canPop()) {
                  nav.pop();
                } else {
                  nav.pushReplacementNamed('/');
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back,
                  color: Color(0xFF1A1A1A),
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiBaseDebugBadge extends StatelessWidget {
  const _ApiBaseDebugBadge();

  @override
  Widget build(BuildContext context) {
    final label = 'API: ${ApiService.baseUrl}';
    final maxBadgeWidth = MediaQuery.of(context).size.width - 28;
    return Positioned(
      right: 12,
      top: 10,
      child: SafeArea(
        child: IgnorePointer(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: maxBadgeWidth.clamp(120, 520).toDouble(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xCC111827),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x66FFFFFF)),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFFF9FAFB),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
