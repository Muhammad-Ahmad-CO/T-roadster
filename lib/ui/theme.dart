import 'package:flutter/material.dart';

/// Shared T Roadster UI theme (sunset palette — matches the reel's
/// pink-purple-orange golden hour, not Color Cover's navy).
class TTheme {
  static const Color deepPurple = Color(0xFF1B0B2E);
  static const Color purple = Color(0xFF2B1055);
  static const Color magenta = Color(0xFFB83280);
  static const Color orange = Color(0xFFFF7E3D);
  static const Color gold = Color(0xFFFFC531);
  static const Color cream = Color(0xFFFFF3E0);
  static const Color panel = Color(0xCC1B0B2E);
  static const Color panelBorder = Color(0x66FFC531);

  static const TextStyle display = TextStyle(
    fontFamily: 'RussoOne',
    color: Colors.white,
    fontSize: 44,
    letterSpacing: 1.5,
  );
  static const TextStyle title = TextStyle(
    fontFamily: 'RussoOne',
    color: Colors.white,
    fontSize: 26,
  );
  static const TextStyle body = TextStyle(
    fontFamily: 'Nunito',
    color: Colors.white,
    fontSize: 16,
  );
  static const TextStyle bodyDim = TextStyle(
    fontFamily: 'Nunito',
    color: Color(0xFFD8CBE8),
    fontSize: 15,
  );
  static const TextStyle goldLabel = TextStyle(
    fontFamily: 'RussoOne',
    color: gold,
    fontSize: 15,
    letterSpacing: 1.0,
  );

  /// Big gold primary button (72 px tall on Home, like Color Cover's
  /// START BATTLE).
  static Widget goldButton({
    required String label,
    required VoidCallback onPressed,
    double height = 64,
    double fontSize = 24,
    bool autofocus = false,
  }) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ElevatedButton(
        autofocus: autofocus,
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: const Color(0xFF1B0B2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 6,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'RussoOne',
            fontSize: fontSize,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  static Widget ghostButton({
    required String label,
    required VoidCallback onPressed,
    double height = 56,
  }) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white54, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'RussoOne',
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  static Widget panelBox({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: panelBorder, width: 2),
      ),
      child: child,
    );
  }

  /// Small "coming soon" badge — a dead button with no feedback is never
  /// shipped (SPEC §3.2).
  static Widget comingSoonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: magenta,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'SOON',
        style: TextStyle(
          fontFamily: 'RussoOne',
          fontSize: 10,
          color: Colors.white,
        ),
      ),
    );
  }
}
