import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Public widgets
// ---------------------------------------------------------------------------

/// Full logo: icon + wordmark + tagline. Use on splash / onboarding.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandIcon(size: 128),
        const SizedBox(height: 20),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'My',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                  color: const Color(0xFFFFB300),
                  letterSpacing: -1.0,
                ),
              ),
              TextSpan(
                text: 'Budga',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'MINDFUL MONEY',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.4),
            letterSpacing: 3.5,
          ),
        ),
      ],
    );
  }
}

/// Icon only — for compact use or app-icon export reference.
class BrandIcon extends StatelessWidget {
  final double size;
  const BrandIcon({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _BuddhaIconPainter()),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _BuddhaIconPainter extends CustomPainter {
  const _BuddhaIconPainter();

  static const _indigo   = Color(0xFF5C00F2);
  static const _indigoMd = Color(0xFF7B2FFF);
  static const _indigoLt = Color(0xFF9B6FFF);
  static const _gold     = Color(0xFFFFB300);
  static const _goldDk   = Color(0xFFFF8F00);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    _halo(canvas, w, h);
    _body(canvas, w, h);
    _head(canvas, w, h);
    _coin(canvas, w, h);
  }

  // ── Halo glow + ring ────────────────────────────────────────────────────

  void _halo(Canvas canvas, double w, double h) {
    final c = Offset(w * 0.5, h * 0.44);
    final r = w * 0.41;

    canvas.drawCircle(
      c, r * 1.18,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _indigoMd.withValues(alpha: 0.38),
            _indigo.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.18)),
    );

    canvas.drawCircle(
      c, r,
      Paint()
        ..color = _indigoLt.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.016
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  // ── Seated robe / body ───────────────────────────────────────────────────

  void _body(Canvas canvas, double w, double h) {
    final cx  = w * 0.5;
    final ty  = h * 0.42;   // shoulders
    final by  = h * 0.83;   // knees bottom
    final tw  = w * 0.20;   // half-width at shoulders
    final bw  = w * 0.43;   // half-width at knees

    final path = Path()
      ..moveTo(cx - tw, ty)
      ..quadraticBezierTo(cx - bw * 1.08, h * 0.64, cx - bw, by)
      ..quadraticBezierTo(cx, h * 0.88,   cx + bw, by)
      ..quadraticBezierTo(cx + bw * 1.08, h * 0.64, cx + tw, ty)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_indigoLt, _indigo],
        ).createShader(Rect.fromLTWH(cx - bw, ty, bw * 2, by - ty)),
    );
  }

  // ── Head, topknot, bindi, eyes, smile ────────────────────────────────────

  void _head(Canvas canvas, double w, double h) {
    final cx = w * 0.5;
    final cy = h * 0.265;
    final r  = w * 0.148;

    // Head sphere
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: [_indigoLt, _indigoMd],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );

    // Topknot (ushnisha)
    canvas.drawCircle(
      Offset(cx, cy - r * 0.82), r * 0.36,
      Paint()..color = _indigoMd,
    );

    // Bindi dot
    canvas.drawCircle(
      Offset(cx, cy - r * 0.06), r * 0.115,
      Paint()..color = _gold,
    );

    // Closed eyes (two small downward arcs)
    for (final sign in [-1.0, 1.0]) {
      final eye = Path()
        ..moveTo(cx + sign * r * 0.33, cy + r * 0.14)
        ..quadraticBezierTo(
          cx + sign * r * 0.20, cy + r * 0.28,
          cx + sign * r * 0.07, cy + r * 0.14,
        );
      canvas.drawPath(
        eye,
        Paint()
          ..color = _indigo.withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.016
          ..strokeCap = StrokeCap.round,
      );
    }

    // Smile
    final smile = Path()
      ..moveTo(cx - r * 0.26, cy + r * 0.38)
      ..quadraticBezierTo(cx, cy + r * 0.54, cx + r * 0.26, cy + r * 0.38);
    canvas.drawPath(
      smile,
      Paint()
        ..color = _indigo.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.018
        ..strokeCap = StrokeCap.round,
    );
  }

  // ── Golden coin with ₹ ──────────────────────────────────────────────────

  void _coin(Canvas canvas, double w, double h) {
    final cx = w * 0.5;
    final cy = h * 0.665;
    final r  = w * 0.105;

    // Glow
    canvas.drawCircle(
      Offset(cx, cy), r * 1.65,
      Paint()
        ..shader = RadialGradient(
          colors: [_gold.withValues(alpha: 0.32), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.65)),
    );

    // Coin face
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [const Color(0xFFFFE082), _goldDk],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );

    // ₹ symbol
    final tp = TextPainter(
      text: TextSpan(
        text: '₹',
        style: TextStyle(
          color: _indigo,
          fontSize: r * 1.15,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
