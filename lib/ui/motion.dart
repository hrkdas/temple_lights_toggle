import 'package:flutter/material.dart';

/// Centralized motion durations and curves for serene temple lighting animations.
class AppMotion {
  AppMotion._();

  static const Duration quick = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 280);
  static const Duration smoothReturn = Duration(milliseconds: 450);
  static const Duration pulse = Duration(milliseconds: 1400);

  static const Curve curveEnter = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;
  static const Curve curveStandard = Curves.easeInOutCubic;
}

Route<T> smoothFadeRoute<T>(Widget Function(BuildContext) builder) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) {
        return child;
      }
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.curveEnter);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
    transitionDuration: AppMotion.standard,
  );
}
