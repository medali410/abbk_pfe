import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomNotificationToast extends StatefulWidget {
  final String title;
  final String subtitle1;
  final String subtitle2;
  final String description;
  final String time;
  final bool isCompleted;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  const CustomNotificationToast({
    Key? key,
    required this.title,
    required this.subtitle1,
    required this.subtitle2,
    required this.description,
    required this.time,
    required this.isCompleted,
    required this.onAction,
    required this.onDismiss,
  }) : super(key: key);

  @override
  _CustomNotificationToastState createState() => _CustomNotificationToastState();
}

class _CustomNotificationToastState extends State<CustomNotificationToast> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();

    // Auto-dismiss après 8 secondes
    _dismissTimer = Timer(const Duration(seconds: 8), _dismiss);
  }

  void _dismiss() {
    if (mounted) {
      _controller.reverse().then((_) {
        widget.onDismiss();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isCompleted ? const Color(0xFF1E3A28) : const Color(0xFF10283B);
    final borderColor = widget.isCompleted ? Colors.green : Colors.cyan;
    final iconColor = widget.isCompleted ? Colors.greenAccent : Colors.cyanAccent;

    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offsetAnimation,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor.withOpacity(0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                  BoxShadow(
                    color: borderColor.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(widget.isCompleted ? Icons.check_circle : Icons.rocket_launch, color: iconColor, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      Text(
                        widget.time,
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(widget.isCompleted ? Icons.engineering : Icons.person, widget.subtitle1),
                            const SizedBox(height: 4),
                            _buildInfoRow(Icons.precision_manufacturing, widget.subtitle2),
                            const SizedBox(height: 8),
                            Text(
                              '"${widget.description}"',
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          _dismissTimer?.cancel();
                          _dismiss();
                          widget.onAction();
                        },
                        icon: Icon(widget.isCompleted ? Icons.description : Icons.remove_red_eye, color: iconColor, size: 16),
                        label: Text(
                          widget.isCompleted ? 'VOIR RAPPORT' : 'AFFICHER',
                          style: GoogleFonts.inter(color: iconColor, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: iconColor.withOpacity(0.1),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          _dismissTimer?.cancel();
                          _dismiss();
                        },
                        icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                        label: Text('Ignorer', style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
