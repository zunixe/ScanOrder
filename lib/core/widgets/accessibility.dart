import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// Accessibility utility extensions and helpers
extension AccessibilityExtensions on Widget {
  /// Add semantic label for screen readers
  Widget withSemantics({
    String? label,
    String? hint,
    bool? button,
    bool? image,
    bool? header,
    bool? selected,
    bool? enabled,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      button: button,
      image: image,
      header: header,
      selected: selected,
      enabled: enabled,
      child: this,
    );
  }
}

/// Accessible icon button with proper semantics
class AccessibleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final String? semanticLabel;
  final bool enabled;
  final Color? color;
  final double size;

  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.semanticLabel,
    this.enabled = true,
    this.color,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? tooltip,
      button: true,
      enabled: enabled,
      child: IconButton(
        icon: Icon(icon, size: size, color: color),
        onPressed: enabled ? onPressed : null,
        tooltip: tooltip,
      ),
    );
  }
}

/// Accessible list tile with proper semantics
class AccessibleListTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool selected;
  final bool enabled;

  const AccessibleListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    this.selected = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      selected: selected,
      enabled: enabled,
      child: ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: enabled ? onTap : null,
        selected: selected,
      ),
    );
  }
}

/// High contrast text for better accessibility
class HighContrastText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const HighContrastText({
    super.key,
    required this.data,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = style ?? defaultStyle;
    
    // Ensure minimum contrast ratio by using bold font weight if not specified
    final highContrastStyle = effectiveStyle.copyWith(
      fontWeight: effectiveStyle.fontWeight ?? FontWeight.w600,
      height: effectiveStyle.height ?? 1.3, // Better line height for readability
    );

    return Text(
      data,
      style: highContrastStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Large touch target wrapper for better accessibility
class LargeTouchTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double minSize;
  final EdgeInsets padding;

  const LargeTouchTarget({
    super.key,
    required this.child,
    required this.onTap,
    this.minSize = 48.0,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: BoxConstraints(
            minWidth: minSize,
            minHeight: minSize,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Screen reader announcement utility
class AccessibilityAnnouncement {
  static void announce(BuildContext context, String message, {bool assertive = false}) {
    SemanticsService.announce(message, TextDirection.ltr);
  }

  static void announceError(BuildContext context, String message) {
    announce(context, message, assertive: true);
  }

  static void announceSuccess(BuildContext context, String message) {
    announce(context, message, assertive: false);
  }
}

/// Focus management for accessibility
class FocusTrap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onEscape;

  const FocusTrap({
    super.key,
    required this.child,
    this.onEscape,
  });

  @override
  State<FocusTrap> createState() => _FocusTrapState();
}

class _FocusTrapState extends State<FocusTrap> {
  final FocusScopeNode _focusScopeNode = FocusScopeNode();

  @override
  void dispose() {
    _focusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: _focusScopeNode,
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.escape): const ActivateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (ActivateIntent intent) {
                widget.onEscape?.call();
                return null;
              },
            ),
          },
          child: widget.child,
        ),
      ),
    );
  }
}
