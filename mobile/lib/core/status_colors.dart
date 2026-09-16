import 'package:flutter/material.dart';

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.live,
    required this.onLive,
    required this.delayed,
    required this.onDelayed,
    required this.offline,
    required this.onOffline,
  });

  final Color live;
  final Color onLive;
  final Color delayed;
  final Color onDelayed;
  final Color offline;
  final Color onOffline;

  static const light = StatusColors(
    live: Color(0xFF22A06B),
    onLive: Colors.white,
    delayed: Color(0xFFE8A33D),
    onDelayed: Colors.white,
    offline: Color(0xFFDC3545),
    onOffline: Colors.white,
  );

  static const dark = StatusColors(
    live: Color(0xFF3DD68C),
    onLive: Color(0xFF00391F),
    delayed: Color(0xFFF2B84B),
    onDelayed: Color(0xFF3D2900),
    offline: Color(0xFFFF6B6B),
    onOffline: Color(0xFF3F0A0A),
  );

  @override
  StatusColors copyWith({
    Color? live,
    Color? onLive,
    Color? delayed,
    Color? onDelayed,
    Color? offline,
    Color? onOffline,
  }) {
    return StatusColors(
      live: live ?? this.live,
      onLive: onLive ?? this.onLive,
      delayed: delayed ?? this.delayed,
      onDelayed: onDelayed ?? this.onDelayed,
      offline: offline ?? this.offline,
      onOffline: onOffline ?? this.onOffline,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      live: Color.lerp(live, other.live, t)!,
      onLive: Color.lerp(onLive, other.onLive, t)!,
      delayed: Color.lerp(delayed, other.delayed, t)!,
      onDelayed: Color.lerp(onDelayed, other.onDelayed, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      onOffline: Color.lerp(onOffline, other.onOffline, t)!,
    );
  }
}

enum LiveStatus { live, delayed, offline }

extension StatusColorsX on BuildContext {
  StatusColors get statusColors =>
      Theme.of(this).extension<StatusColors>() ?? StatusColors.light;

  Color colorFor(LiveStatus status) => switch (status) {
        LiveStatus.live => statusColors.live,
        LiveStatus.delayed => statusColors.delayed,
        LiveStatus.offline => statusColors.offline,
      };
}
