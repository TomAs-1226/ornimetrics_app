/// Shared Ornimetrics feeder design system.
///
/// One consistent set of Material 3 building blocks used across every feeder
/// screen: spacing tokens, cards, section headers, stat tiles, skeleton
/// loaders, empty/error/offline states, animated counters, a species avatar
/// and welfare-screening helpers. Keeping these here guarantees the feeder
/// surface looks coherent in both light and dark themes and avoids one-off
/// colours / paddings / sizes.

library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/feeder_models.dart';

/// Spacing + radius tokens. Use these instead of bare numbers.
class FeederSpacing {
  FeederSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double radius = 16;
  static const double radiusSm = 10;
  static const EdgeInsets screen = EdgeInsets.all(lg);
  static const EdgeInsets card = EdgeInsets.all(lg);
}

/// User-facing welfare copy. Welfare is *always* a screening flag, never a
/// diagnosis — this wording keeps a human in the loop.
class WelfareCopy {
  WelfareCopy._();
  static const String screeningNote =
      'This is an automated screening flag, not a diagnosis. Birds can look '
      'unusual for harmless reasons. If you\'re concerned, watch for repeated '
      'flags and contact a licensed wildlife rehabilitator.';
  static const String findRehabber = 'Find a wildlife rehabber';
  static const String rehabberUrl =
      'https://www.google.com/search?q=wildlife+rehabilitator+near+me';
  static const String gentleHeadline = 'A bird may need a closer look';
}

/// Whether the user has asked the OS to reduce motion. Animations should fall
/// back to instant when true.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Relative "time ago" string for a timestamp.
String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.isNegative) return 'just now';
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final weeks = diff.inDays ~/ 7;
  if (weeks < 5) return '${weeks}w ago';
  final months = diff.inDays ~/ 30;
  if (months < 12) return '${months}mo ago';
  return '${diff.inDays ~/ 365}y ago';
}

/// A consistent card surface. Optionally tappable with a ripple.
class FeederCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  const FeederCard({
    super.key,
    required this.child,
    this.padding = FeederSpacing.card,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(FeederSpacing.radius),
    );
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? scheme.surfaceContainerHigh,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Section header with an icon and optional trailing action.
class FeederSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const FeederSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FeederSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: FeederSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A compact metric tile (value + label + icon) for digest rows.
class FeederStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color? accent;

  const FeederStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return FeederCard(
      padding: const EdgeInsets.symmetric(vertical: FeederSpacing.lg, horizontal: FeederSpacing.sm),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: FeederSpacing.sm),
          AnimatedCount(
            value: value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: FeederSpacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// An integer that animates (tweens) when its value changes.
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;

  const AnimatedCount({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 600),
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) {
      return Text('$value', style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// A circular avatar derived deterministically from a species name, with the
/// species' initials. Gives every species a stable colour without art assets.
class SpeciesAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool distressed;

  const SpeciesAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.distressed = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hue = (name.hashCode % 360).abs().toDouble();
    final bg = HSLColor.fromAHSL(
            1, hue, 0.45, Theme.of(context).brightness == Brightness.dark ? 0.32 : 0.82)
        .toColor();
    final fg = HSLColor.fromAHSL(
            1, hue, 0.6, Theme.of(context).brightness == Brightness.dark ? 0.85 : 0.30)
        .toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: distressed
            ? Border.all(color: scheme.error, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.34,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }
}

/// Small "screening" chip shown when a sighting was flagged for welfare.
class DistressChip extends StatelessWidget {
  final double? distressZ;
  const DistressChip({super.key, this.distressZ});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FeederSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.health_and_safety_outlined,
              size: 14, color: scheme.onErrorContainer),
          const SizedBox(width: 4),
          Text(
            'Welfare check',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// A confidence percentage pill (e.g. 87%).
class ConfidencePill extends StatelessWidget {
  final double? confidence;
  const ConfidencePill({super.key, this.confidence});

  @override
  Widget build(BuildContext context) {
    if (confidence == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final pct = (confidence! * 100).clamp(0, 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FeederSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$pct%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// A shimmering skeleton block for loading states.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.06), base);
    final radius = widget.borderRadius ?? BorderRadius.circular(8);
    if (reduceMotion(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: radius),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t) + 1, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// A list of skeleton rows for list loading states.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: FeederSpacing.md),
          child: Row(
            children: [
              const SkeletonBox(
                width: 44,
                height: 44,
                borderRadius: BorderRadius.all(Radius.circular(22)),
              ),
              const SizedBox(width: FeederSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 160, height: 14),
                    SizedBox(height: 8),
                    SkeletonBox(width: 90, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A consistent empty state.
class FeederEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const FeederEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FeederSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: FeederSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: FeederSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: FeederSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A consistent, retry-able error state.
class FeederErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const FeederErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FeederSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: scheme.error),
            const SizedBox(height: FeederSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: FeederSpacing.lg),
            FilledButton.tonalIcon(
              onPressed: () {
                HapticFeedback.selectionClick();
                onRetry();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A slim offline banner shown above last-known data.
class OfflineBanner extends StatelessWidget {
  final DateTime? lastUpdated;
  const OfflineBanner({super.key, this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: FeederSpacing.lg, vertical: FeederSpacing.sm),
      color: scheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: FeederSpacing.sm),
          Expanded(
            child: Text(
              lastUpdated == null
                  ? 'Offline — can\'t reach the feeder'
                  : 'Offline — showing data from ${relativeTime(lastUpdated!)}',
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tiny sparkline painter for distress / health trends.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  final double? threshold;

  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 64,
    this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(
          values: values,
          color: color,
          threshold: threshold,
          gridColor: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double? threshold;
  final Color gridColor;

  _SparkPainter({
    required this.values,
    required this.color,
    required this.gridColor,
    this.threshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = math.max(values.reduce(math.max), threshold ?? 0) * 1.15 + 0.001;
    final minV = math.min(values.reduce(math.min), 0);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    double x(int i) => values.length == 1
        ? size.width / 2
        : size.width * i / (values.length - 1);
    double y(double v) => size.height - ((v - minV) / range) * size.height;

    // Threshold line.
    if (threshold != null) {
      final tp = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      final ty = y(threshold!);
      const dash = 5.0;
      for (double dx = 0; dx < size.width; dx += dash * 2) {
        canvas.drawLine(Offset(dx, ty), Offset(dx + dash, ty), tp);
      }
    }

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final p = Offset(x(i), y(values[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    // Fill under the line.
    final fill = Path.from(path)
      ..lineTo(x(values.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = color.withValues(alpha: 0.12),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Last point dot.
    canvas.drawCircle(
      Offset(x(values.length - 1), y(values.last)),
      3.5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color || old.threshold != threshold;
}

/// Helper to format a [Sighting]/[WelfareAlert] individual label.
String individualLabel(String? individual) =>
    (individual != null && individual.isNotEmpty) ? individual : 'Unknown bird';

/// Clean species display (re-exported convenience).
String speciesDisplay(String raw) => cleanSpeciesName(raw);
