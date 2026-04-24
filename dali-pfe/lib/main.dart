import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_page.dart';
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
    if (role == 'conception') {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/conception-observatory');
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
  }

  @override
  Widget build(BuildContext context) => const LoginPage();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
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
            const _GlobalBackButtonOverlay(),
          ],
        );
      },
      routes: {
        '/': (context) => const SessionEntry(),
        '/dashboard': (context) => const DashboardPage(),
        '/client-dashboard': (context) => const ClientDashboardPage(),
        '/add-client': (context) => const AddClientPage(),
        '/team': (context) => const ProjectTeamPage(),
        '/technician-profile': (context) => const TechnicianProfilePage(),
        '/technician-terminal': (context) => const TechnicianTerminalPage(),
        '/technician-collaboration': (context) => const TechnicianCollaborationPage(),
        '/conception-observatory': (context) => const ConceptionObservatoryPage(),


        '/maintenance-login': (context) => const MaintenanceLoginPage(),
        '/maintenance-dashboard': (context) => const MaintenanceDashboardPage(),
        '/add-technician': (context) => const AddTechnicianPage(),
        '/machine-team': (context) => const MachineTeamPage(),
        '/machine-detail': (context) =>
            const MachineDetailAiPage(machineId: 'MAC_HATHA'),
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
                  nav.pushReplacementNamed('/dashboard');
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_back, color: Color(0xFF1A1A1A), size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
