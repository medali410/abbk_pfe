import 'package:flutter/material.dart';

/// A card that subtly scales up on hover (web/desktop) and scales down on tap (mobile).
/// Provides a premium, interactive feel across all roles' dashboards.
class AnimatedCard extends StatefulWidget {
  const AnimatedCard({
    super.key,
    required this.child,
    this.onTap,
    this.hoverScale = 1.015,
    this.pressScale = 0.975,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.elevation = 2.0,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double hoverScale;
  final double pressScale;
  final double borderRadius;
  final EdgeInsets padding;
  final Color? color;
  final double elevation;

  @override
  State<AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<AnimatedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: widget.hoverScale).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  double get _targetScale {
    if (_isPressed) return widget.pressScale;
    if (_isHovered) return widget.hoverScale;
    return 1.0;
  }

  void _updateScale() {
    if (_isPressed) {
      _ctrl.animateTo(
        (widget.pressScale - 1.0) / (widget.hoverScale - 1.0),
        duration: const Duration(milliseconds: 80),
      );
    } else if (_isHovered) {
      _ctrl.forward(from: _ctrl.value);
    } else {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor =
        widget.color ?? Theme.of(context).colorScheme.surfaceContainerHighest;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _updateScale();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _updateScale();
      },
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          _ctrl.animateTo(
            1.0,
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeIn,
          );
        },
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _updateScale();
          widget.onTap?.call();
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
          _updateScale();
        },
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Card(
            color: cardColor,
            elevation: widget.elevation,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            child: Padding(
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
