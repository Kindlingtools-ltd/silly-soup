import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// A big, chunky, rounded button.
///
/// Never smaller than [SoupMetrics.minTapTarget] in either direction: a
/// three-year-old aiming with a whole hand needs a target, not a link.
class SoupButton extends StatefulWidget {
  const SoupButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.outlined = false,
    this.width,
    this.scale = 1.0,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool outlined;
  final double? width;
  final double scale;

  @override
  State<SoupButton> createState() => _SoupButtonState();
}

class _SoupButtonState extends State<SoupButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final background = !enabled
        ? SoupColours.disabled
        : widget.outlined
        ? SoupColours.surface
        : (widget.backgroundColor ?? SoupColours.primary);
    // A filled button keeps its white label when it is disabled unless this
    // says otherwise, and white on the disabled fill is not a colour, it is
    // a disappearance.
    final foreground = !enabled
        ? SoupColours.disabledText
        : widget.outlined
        ? SoupColours.textPrimary
        : (widget.foregroundColor ?? SoupColours.textOnBrand);
    final height = SoupMetrics.minTapTarget * widget.scale;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: Container(
            width: widget.width,
            height: height,
            constraints: BoxConstraints(minWidth: height),
            padding: EdgeInsets.symmetric(horizontal: 28 * widget.scale),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(
                SoupMetrics.cardRadius * widget.scale,
              ),
              border: widget.outlined
                  ? Border.all(color: SoupColours.border, width: 2)
                  : null,
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: foreground, size: 28 * widget.scale),
                  SizedBox(width: 12 * widget.scale),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    style: SoupTypography.button(
                      context,
                    ).copyWith(color: foreground, fontSize: 18 * widget.scale),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
