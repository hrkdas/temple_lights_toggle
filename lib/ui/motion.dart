import 'package:flutter/material.dart';

Route<T> smoothFadeRoute<T>(Widget Function(BuildContext) builder) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(opacity: curved, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(curved), child: child));
    },
    transitionDuration: const Duration(milliseconds: 260),
  );
}
