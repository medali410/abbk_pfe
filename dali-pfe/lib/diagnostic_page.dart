import 'dart:ui';
import 'package:flutter/material.dart';
import 'add_conception_page.dart';
import 'package:google_fonts/google_fonts.dart';

class DiagnosticPage extends StatefulWidget {
  const DiagnosticPage({super.key});

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  
  // Colors mapped from Tailwind JSON
  static const Color _bg = Color(0xFF10102b);
  static const Color _surfaceContainerLow = Color(0xFF191934);
  static const Color _surfaceContainer = Color(0xFF1d1d38);
  static const Color _surfaceContainerHigh = Color(0xFF272743);
  static const Color _surfaceContainerHighest = Color(0xFF32324e);
  
  static const Color _primary = Color(0xFFffb692);
  static const Color _primaryContainer = Color(0xFFff6e00);
  static const Color _onPrimary = Color(0xFF552000);
  
  static const Color _secondary = Color(0xFF75d1ff);
  static const Color _secondaryFixed = Color(0xFFc2e8ff);
  
  static const Color _tertiary = Color(0xFFefb1f9);
  
  static const Color _error = Color(0xFFffb4ab);
  
  static const Color _onSurface = Color(0xFFe2dfff);
  static const Color _onSurfaceVariant = Color(0xFFe2bfb0);
  static const Color _outlineVariant = Color(0xFF594136);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddConceptionPage())), backgroundColor: Color(0xFFff6e00), icon: const Icon(Icons.add, color: Colors.white), label: Text('AJOUTER CONCEPTION', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white))),
      body: Column(
        children: [
          _buildTopNavBar(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- Top Navigation Bar ---
  Widget _buildTopNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(color: _bg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text('KINETIC OBSERVATORY', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: _primaryContainer, letterSpacing: -1)),
              const SizedBox(width: 32),
              _topNavTab('System Health', isActive: false),
              const SizedBox(width: 24),
              _topNavTab('Live Feed', isActive: true),
            ],
          ),
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: Colors.transparent),
                    child: const Icon(Icons.notifications_active_outlined, color: _primaryContainer),
                  ),
                  Positioned(
                    top: 8, right: 8,
                    child: Container(width: 8, height: 8, decoration: BoxDecoration(color: _error, shape: BoxShape.circle, border: Border.all(color: _bg, width: 2))),
                  )
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.settings_input_component_outlined, color: _onSurfaceVariant),
              const SizedBox(width: 16),
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: _surfaceContainerHigh, borderRadius: BorderRadius.circular(4), border: Border.all(color: _outlineVariant.withOpacity(0.3))),
                clipBehavior: Clip.antiAlias,
                child: Image.network('https://lh3.googleusercontent.com/aida-public/AB6AXuBxKXHQWRyqwtOExP_pXc8glZThTMK3qRSbOZ4Cbc67h0GPGERDz1r54I6HWYhZzyyPJlb2-Lo43aqi1iNrESbCK_YWUZzxsD-3zzCCIWM2cS1P0MduZtSGcIpgJjYvDMRKHpQnvfCIPVfbk5k1yavFjWXng1HQBWrX-CFBw5G9SoW4ZhBJgKtSGPoPyPZJkmQ5noBGRlL1N-yGGNxcvHrzsVxLeB7jjUuNy7qNzFiNfLfTflM1t4fuEj0brmCY9ISzNzhvRx8pfLo', fit: BoxFit.cover),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _topNavTab(String title, {bool isActive = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: isActive ? const Border(bottom: BorderSide(color: _primaryContainer, width: 2)) : null,
      ),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: isActive ? _primaryContainer : _onSurfaceVariant.withOpacity(0.7)),
      ),
    );
  }

  // --- Sidebar ---
  Widget _buildSidebar() {
    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        border: Border(right: BorderSide(color: _outlineVariant.withOpacity(0.15))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: _primaryContainer, borderRadius: BorderRadius.circular(4), boxShadow: [BoxShadow(color: _primaryContainer.withOpacity(0.2), blurRadius: 10)]),
                  child: const Icon(Icons.person, color: Colors.white), // close to 'pregnancy' layout? Using person icon
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONCEPTION', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
                    Text('Active Session', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: _primaryContainer, letterSpacing: 1)),
                  ],
                )
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _sidebarItem(Icons.insert_chart_outlined, 'Monitoring', true),
                _sidebarItem(Icons.account_tree_outlined, 'Architecture', false),
                _sidebarItem(Icons.psychology_outlined, 'Psychology', false),
                _sidebarItem(Icons.sensors_outlined, 'Telemetry', false),
                _sidebarItem(Icons.view_in_ar_outlined, '3D Assets', false),
                _sidebarItem(Icons.group_work_outlined, 'Coordination', false),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_primaryContainer, _primary]),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: _primaryContainer.withOpacity(0.1), blurRadius: 10)],
                  ),
                  alignment: Alignment.center,
                  child: Text('DEPLOY UPDATE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _onPrimary, letterSpacing: 2)),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: _outlineVariant.withOpacity(0.1)))),
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      _sidebarFooterItem(Icons.help_outline, 'Support'),
                      const SizedBox(height: 8),
                      _sidebarFooterItem(Icons.history_outlined, 'Logs'),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String title, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: isActive ? const EdgeInsets.only(left: 4) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: isActive ? _surfaceContainerHigh : Colors.transparent,
        border: isActive ? const Border(left: BorderSide(color: _primaryContainer, width: 4)) : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: isActive ? _primaryContainer : _onSurfaceVariant.withOpacity(0.6), size: 18),
          const SizedBox(width: 12),
          Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w500, color: isActive ? _primaryContainer : _onSurfaceVariant.withOpacity(0.6), letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _sidebarFooterItem(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: _onSurfaceVariant.withOpacity(0.6), size: 14),
        const SizedBox(width: 12),
        Text(title.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w500, color: _onSurfaceVariant.withOpacity(0.6), letterSpacing: 2)),
      ],
    );
  }

  // --- Main Content Canvas ---
  Widget _buildMainContent() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        IntrinsicHeight( // Ensures all three columns in the row share the same height constraint if possible, but Row with crossAxisAlignment stretch works better with fixed heights or flexible. We'll use Expanded inside a Row with normal cross alignment.
          child: Row(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Expanded(flex: 5, child: _buildColLeft()),
               const SizedBox(width: 24),
               Expanded(flex: 4, child: _buildColMiddle()),
               const SizedBox(width: 24),
               Expanded(flex: 3, child: _buildColRight()),
             ],
          ),
        ),
        const SizedBox(height: 24),
        _buildBottomDetailedGraphs(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Panneau de Contrôle Conception & Monitoring Temps Réel'.toUpperCase(), style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: _onSurface, letterSpacing: -1)),
            const SizedBox(height: 8),
            Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_,__) => Container(
                        width: 16, height: 16,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF66BB6A).withOpacity(_pulseController.value * 0.3)),
                        transform: Matrix4.identity()..scale(1.0 + (_pulseController.value * 0.5)),
                      ),
                    ),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF66BB6A), shape: BoxShape.circle)),
                  ],
                ),
                const SizedBox(width: 8),
                Text('Système Opérationnel'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
                const SizedBox(width: 16),
                Text('Station: Hall B - Grid 14-A'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant.withOpacity(0.4), letterSpacing: 2)),
              ],
            )
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                 Text('14:23:08', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: _primary)),
                 const SizedBox(width: 8),
                 Text('GMT+1', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: _primary.withOpacity(0.5))),
              ],
            ),
            Text('24 MAI 2024', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
          ],
        )
      ],
    );
  }

  // COL LEFT (3D View + GPS)
  Widget _buildColLeft() {
    return Column(
      children: [
        // 3D View
        Container(
          height: 450,
          decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
               Positioned.fill(
                 child: ColorFiltered(
                   colorFilter: const ColorFilter.mode(Colors.black, BlendMode.saturation), // grayscale
                   child: Image.asset('assets/images/turbine.png', fit: BoxFit.cover, opacity: const AlwaysStoppedAnimation(0.4)),
                 )
               ),
               Padding(
                 padding: const EdgeInsets.all(24),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Text('Visualisation Structurelle'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _primary, letterSpacing: 2)),
                     Text('Turbine Core - TC-01', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: _onSurface)),
                   ],
                 ),
               ),
               // Markers
               Positioned(
                 top: 150, left: 200,
                 child: Stack(
                   clipBehavior: Clip.none,
                   alignment: Alignment.center,
                   children: [
                     Container(width: 16, height: 16, decoration: BoxDecoration(color: _error, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _error.withOpacity(0.6), blurRadius: 15)])),
                     Positioned(
                       top: -30, left: -10,
                       child: Container(
                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                         decoration: BoxDecoration(color: _surfaceContainerHighest, borderRadius: BorderRadius.circular(4), border: Border.all(color: _outlineVariant.withOpacity(0.3))),
                         child: Text('ZONES DE CHALEUR CRITIQUE', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurface)),
                       ),
                     )
                   ],
                 ),
               ),
               Positioned(
                 bottom: 150, right: 150,
                 child: Stack(
                   clipBehavior: Clip.none,
                   alignment: Alignment.center,
                   children: [
                     Container(width: 12, height: 12, decoration: BoxDecoration(color: _secondary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _secondary.withOpacity(0.4), blurRadius: 10)])),
                     Positioned(
                       bottom: -30, right: -10,
                       child: Container(
                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                         decoration: BoxDecoration(color: _surfaceContainerHighest, borderRadius: BorderRadius.circular(4), border: Border.all(color: _outlineVariant.withOpacity(0.3))),
                         child: Text('CAPTEUR DE VIBRATION OK', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurface)),
                       ),
                     )
                   ],
                 ),
               ),
               Positioned(
                 bottom: 24, left: 24, right: 24,
                 child: Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(color: _surfaceContainerHighest.withOpacity(0.6), border: Border.all(color: _outlineVariant.withOpacity(0.1)), borderRadius: BorderRadius.circular(4)),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                         Wrap(
                           spacing: 12,
                           children: [
                             Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text('ROTATION', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant)),
                                 Text('12,400 RPM', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurface)),
                               ],
                             ),
                             Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text('TEMP_CORE', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant)),
                                 Text('482 �C', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _error)),
                               ],
                             ),
                           ],
                         ),
                         Container(
                           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                           decoration: BoxDecoration(color: _surfaceContainerHigh, borderRadius: BorderRadius.circular(4), border: Border.all(color: _outlineVariant.withOpacity(0.3))),
                           child: Text('EXPLODED VIEW', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurface)),
                         )
                      ],
                    ),
                   ),
                 ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // GPS
        Container(
          padding: const EdgeInsets.all(24),
           decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text('Localisation Géospatiale'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _primary, letterSpacing: 2)),
                       Text('Station Centrale - Hall B', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface)),
                     ],
                   ),
                   const Icon(Icons.location_on_outlined, color: _secondary),
                 ],
               ),
               const SizedBox(height: 16),
               Container(
                 height: 120, width: double.infinity,
                 decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: Colors.black),
                 clipBehavior: Clip.antiAlias,
                 child: Stack(
                   fit: StackFit.expand,
                   children: [
                     Opacity(opacity: 0.3, child: Image.network('https://lh3.googleusercontent.com/aida-public/AB6AXuCIpXgOcTHBhw73ZlLfeVc3w-T77_fkyX7JeZYLDZMcBj-RnmKq3YMMd4-9RzzBNkWk83K6aMUJQtbZoss0IJC4_79_qsKEac5hsK7kgiwM3IxYVUoLH4ND3y1sQhqdhcIugBivLtAVhk5RiwVn0X-s1l5j1tF-7eiZBqQNmO6HMPNk_rXIWZ6-y-le6_zKnBqLJ5G-mG09FnR0HXq4vxXgf7S9umkSyGUCIhHnFlIH966scCNiEc33QYRw6b9fo74nR2z3dNwVVbU', fit: BoxFit.cover)),
                     Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [_surfaceContainerLow, Colors.transparent]))),
                   ],
                 )
               ),
               const SizedBox(height: 16),
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LATITUDE', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant, letterSpacing: 2)),
                        Text('36.8065', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LONGITUDE', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant, letterSpacing: 2)),
                        Text('10.1815', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
                      ],
                    ),
                 ],
               )
             ],
           ),
        )
      ],
    );
  }

  // COL MIDDLE (Telemetry + Chat)
  Widget _buildColMiddle() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Multi-Sensor Telemetry'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _primary, letterSpacing: 2)),
              const SizedBox(height: 24),
              _buildProgressTelemetry(Icons.thermostat_outlined, 'Thermique', '42.8 °C', _error, 0.75),
              const SizedBox(height: 24),
              _buildProgressTelemetry(Icons.compress_outlined, 'Pression', '104.2 PSI', _secondary, 0.5),
              const SizedBox(height: 24),
              _buildProgressTelemetry(Icons.bolt_outlined, 'Énergie', '12.4 kW/h', const Color(0xFFffdbcb), 0.33),
              const SizedBox(height: 24),
              _buildBarTelemetry(Icons.settings_voice_outlined, 'Ultrasonique', 'Normal', _tertiary),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Présence'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                         Text('3', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: _onSurface)),
                         const SizedBox(width: 4),
                         Text('Unités', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 4), decoration: const BoxDecoration(color: Color(0xFF66BB6A), shape: BoxShape.circle)),
                        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 4), decoration: const BoxDecoration(color: Color(0xFF66BB6A), shape: BoxShape.circle)),
                        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 4), decoration: const BoxDecoration(color: Color(0xFF66BB6A), shape: BoxShape.circle)),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Champ Magnétique'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                         Text('0.42', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: _primary)),
                         const SizedBox(width: 4),
                         Text('T', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Icon(Icons.trending_up, color: _primary, size: 12),
                  ],
                ),
              ),
            )
          ],
        ),
        const SizedBox(height: 24),
        Container(
          height: 280,
          decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
               Container(
                 padding: const EdgeInsets.all(16),
                 decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _outlineVariant.withOpacity(0.1)))),
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     Row(
                       children: [
                         Container(
                           width: 32, height: 32,
                           decoration: BoxDecoration(shape: BoxShape.circle, color: _surfaceContainerHigh, border: Border.all(color: _outlineVariant.withOpacity(0.3))),
                           clipBehavior: Clip.antiAlias,
                           child: Image.network('https://lh3.googleusercontent.com/aida-public/AB6AXuCm_fLJBQWW8SzbsGcmfE9GQDsLjJdIJ1Os3eS7lYMKAh9hjjEMZg-Ja2s6pvmW-MpYQZ2BvhF-vFcsy2X28GZMzRoDMT-Vpj0_dZ2EPK8nXDB2oayAUJ3F2Jz4ftNrilUOB4ySZ9uPFDR9DREJBA8NNJ6_ws0_XHnMuIOJNGUQKBqVnZkCDjhVol5zOz5LMEzE-xD9zAY-tziooURMAH5V04Odg8gXD-HreiR39itWsB2NUaZEFmJ3MXoDt30sPwg3i-mNaJcs_mA', fit: BoxFit.cover),
                         ),
                         const SizedBox(width: 12),
                         Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text('Ahmed Ben Ali', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface)),
                             Text('SUR LE TERRAIN', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: const Color(0xFF66BB6A))),
                           ],
                         )
                       ],
                     ),
                     const Icon(Icons.more_vert, color: _onSurfaceVariant, size: 16),
                   ],
                 ),
               ),
               Expanded(
                 child: ListView(
                   padding: const EdgeInsets.all(16),
                   children: [
                     Container(
                       padding: const EdgeInsets.all(8),
                       decoration: BoxDecoration(color: _surfaceContainerHighest.withOpacity(0.5), borderRadius: BorderRadius.circular(4)),
                       width: 200,
                       alignment: Alignment.centerLeft,
                       margin: const EdgeInsets.only(right: 60, bottom: 16),
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text("Capteur IR semble décalé sur l'axe X. Je procède à la vérification physique.", style: GoogleFonts.inter(fontSize: 10, color: _onSurface)),
                           const SizedBox(height: 4),
                           Text("14:18", style: GoogleFonts.inter(fontSize: 8, color: _onSurfaceVariant)),
                         ],
                       ),
                     ),
                     Container(
                       padding: const EdgeInsets.all(8),
                       decoration: BoxDecoration(color: _primaryContainer.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: const Border(right: BorderSide(color: _primary, width: 2))),
                       width: 200,
                       alignment: Alignment.centerRight,
                       margin: const EdgeInsets.only(left: 60),
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text("Compris Ahmed. On attend ton feu vert pour le recalibrage à distance.", style: GoogleFonts.inter(fontSize: 10, color: _onSurface)),
                           const SizedBox(height: 4),
                           Text("14:20", style: GoogleFonts.inter(fontSize: 8, color: _primary)),
                         ],
                       ),
                     )
                   ],
                 )
               ),
               Container(
                 padding: const EdgeInsets.all(16),
                 child: Row(
                   children: [
                     Expanded(
                       child: Container(
                         decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _outlineVariant.withOpacity(0.3)))),
                         child: TextField(
                           style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurface),
                           decoration: InputDecoration(
                             border: InputBorder.none,
                             isDense: true,
                             hintText: 'Entrez une commande...',
                             hintStyle: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurface.withOpacity(0.3)),
                           ),
                         ),
                       ),
                     ),
                     const SizedBox(width: 8),
                     const Icon(Icons.send, color: _primary, size: 14),
                   ],
                 ),
               )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildProgressTelemetry(IconData icon, String title, String val, Color color, double pct) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: const BoxDecoration(color: Color(0xFF32324e), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface)),
                  Text(val, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: color)),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                height: 2, width: double.infinity,
                color: _outlineVariant.withOpacity(0.2),
                child: Row(
                  children: [
                    Expanded(flex: (pct * 100).toInt(), child: Container(decoration: BoxDecoration(color: color, boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)]))),
                    Expanded(flex: 100 - (pct * 100).toInt(), child: const SizedBox()),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildBarTelemetry(IconData icon, String title, String val, Color color) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: const BoxDecoration(color: Color(0xFF32324e), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface)),
                  Text(val, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                height: 32, width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: const Color(0xFF0b0b26).withOpacity(0.5), borderRadius: BorderRadius.circular(4)),
                child: Row(
                  children: List.generate(10, (idx) {
                    final heights = [12.0, 20.0, 16.0, 24.0, 12.0, 20.0, 16.0, 8.0, 24.0, 12.0];
                    final opacities = [0.4, 0.6, 1.0, 0.8, 0.5, 0.7, 0.9, 0.3, 1.0, 0.6];
                    return Container(
                      width: 4, height: heights[idx], margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(color: color.withOpacity(opacities[idx]), borderRadius: BorderRadius.circular(2)),
                    );
                  }),
                ),
              )
             ],
          ),
        )
      ],
    );
  }

  // COL RIGHT (Control Actions + Security + Specs)
  Widget _buildColRight() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Control Actions'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _primary, letterSpacing: 2)),
              const SizedBox(height: 24),
              _buildActionBtn(Icons.system_update_outlined, 'Mise à jour', 'v4.2.1 disponible', _primary),
              const SizedBox(height: 16),
              _buildActionBtn(Icons.settings_backup_restore_outlined, 'Recalibrage', '7 capteurs sélectionnés', _secondary),
              const SizedBox(height: 16),
              _buildActionBtn(Icons.tune_outlined, 'Diagnostics', 'Lancer analyse complète', _tertiary),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _error.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: _error.withOpacity(0.2))),
          child: Column(
            children: [
              Text('Procédure de Sécurité'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _error, letterSpacing: 1)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: _error, borderRadius: BorderRadius.circular(4)),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 8),
                    Text('EMERGENCY STOP', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                  ],
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _surfaceContainerLow.withOpacity(0.6), borderRadius: BorderRadius.circular(4), border: Border.all(color: _outlineVariant.withOpacity(0.2))),
          child: Column(
            children: [
              _buildSpecBar('CPU Load', '24%', _secondary, 0.24),
              const SizedBox(height: 16),
              _buildSpecBar('Network Latency', '14ms', _primary, 0.14),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildActionBtn(IconData icon, String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surfaceContainerHigh, borderRadius: BorderRadius.circular(4), border: Border.all(color: _outlineVariant.withOpacity(0.1))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface)),
                  Text(subtitle.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant.withOpacity(0.5))),
                ],
              )
            ],
          ),
          const Icon(Icons.chevron_right, color: _onSurfaceVariant, size: 12),
        ],
      ),
    );
  }

  Widget _buildSpecBar(String label, String val, Color color, double pct) {
    return Column(
      children: [
        Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
             Text(val, style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _onSurface)),
           ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 4, width: double.infinity,
          decoration: BoxDecoration(color: const Color(0xFF0b0b26), borderRadius: BorderRadius.circular(2)),
          child: Row(
            children: [
              Expanded(flex: (pct * 100).toInt(), child: Container(color: color)),
              Expanded(flex: 100 - (pct * 100).toInt(), child: const SizedBox()),
            ],
          ),
        )
      ],
    );
  }

  // BOTTOM DETAILED GRAPHS
  Widget _buildBottomDetailedGraphs() {
    return Row(
      children: [
        Expanded(child: _buildBottomGraph('Ultrasonic Flux', '88.4 kHz', _primary, const [35,10,25,15,30,10,20])),
        const SizedBox(width: 24),
        Expanded(child: _buildBottomGraph('Infrared Spectrum', '940 nm', _secondary, const [20,15,25,10,30,15,25,5,35,20,25])),
        const SizedBox(width: 24),
        Expanded(child: _buildBottomGraph('Current Draw', '4.8 A', _tertiary, const [30,30,30,10,10,35,35,35,15,15,15])),
      ],
    );
  }

  Widget _buildBottomGraph(String label, String val, Color color, List<double> values) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: color, width: 2))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant)),
               Text(val, style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
            ],
          ),
          SizedBox(height: 40, width: 96, child: CustomPaint(painter: SparklinePainter(color, values)))
        ],
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final Color color;
  final List<double> values;

  SparklinePainter(this.color, this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double maxVal = values.reduce((a, b) => a > b ? a : b);
    final double minVal = values.reduce((a, b) => a < b ? a : b);
    final double range = maxVal - minVal == 0 ? 1 : maxVal - minVal;

    final double xStep = size.width / (values.length - 1);
    final Path path = Path();

    for (int i = 0; i < values.length; i++) {
       final double normalizedY = (values[i] - minVal) / range;
       final double h = size.height * 0.8;
       final double y = size.height - (normalizedY * h) - (size.height * 0.1); 
       final double x = xStep * i;

       if (i == 0) {
         path.moveTo(x, y);
       } else {
         path.lineTo(x, y);
       }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
