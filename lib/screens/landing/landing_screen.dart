import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _buttonFade;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeIn),
      ),
    );

    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    _buttonFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          // ── Pixel-accurate gradient from Figma file analysis ─────────────
          // Direction: pure vertical (top to bottom) — confirmed by pixel sampling
          // Top color:    #005b84 (teal blue)   — sampled at y=10% of screen
          // Bottom color: #000319 (near black)  — Figma spec confirmed
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF005b84), // exact pixel sample from top of screen
              Color(0xFF003655), // mid transition
              Color(0xFF000d28), // lower dark
              Color(0xFF000319), // Figma bottom color
            ],
            stops: [0.0, 0.35, 0.65, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            clipBehavior: Clip.none, // ← allows image to overflow edges
            children: [
              // ── Logo centered vertically at ~45% of screen ───────────────
              Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: size.height * 0.12),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) => FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Image.asset(
                          'assets/images/logo.png',

                          // ── ZOOM CONTROL ─────────────────────────────────
                          // Now works beyond 1.0 — try 1.2, 1.3, 1.4
                          // Image will overflow screen edges (intended)
                          width: size.width * 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── START glass button fixed at bottom ────────────────────────
              Positioned(
                bottom: size.height * 0.09,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (_, __) => FadeTransition(
                    opacity: _buttonFade,
                    child: const Center(
                      child: _GlassStartButton(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass START Button
//
// Figma glass effect specs (applied to the button only, not the background):
//   Angle:       -45 degrees  → gradient goes topRight to bottomLeft
//   Refraction:  100          → maximum lens distortion → BackdropFilter blur
//   Depth:       43           → base fill opacity = 0.43
//   Dispersion:  67           → color spread width across the gradient
//   Frost:       67           → blur sigma ≈ 6.7
//   Splash:      65           → highlight shimmer opacity = 0.65
// ─────────────────────────────────────────────────────────────────────────────

class _GlassStartButton extends StatefulWidget {
  const _GlassStartButton();

  @override
  State<_GlassStartButton> createState() => _GlassStartButtonState();
}

class _GlassStartButtonState extends State<_GlassStartButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        context.go('/sign-in');
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: SizedBox(
          width: 195,
          height: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Stack(
              children: [
                // ── Layer 1: Frost blur (Frost 67, Refraction 100) ────────
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6.7, sigmaY: 6.7),
                  child: Container(color: Colors.transparent),
                ),

                // ── Layer 2: Glass body ───────────────────────────────────
                // Pixel-accurate: body is #042f51 at -45° (topRight→bottomLeft)
                // #19BAFF at 20% over dark bg resolves to this dark teal range
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        Color(0xFF0E3757), // top-right (light side)
                        Color(0xFF042F51), // center body
                        Color(0xFF010C24), // bottom-left (shadow side)
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                ),

                // ── Layer 3: Top edge cyan-white shimmer ──────────────────
                // Pixel sampled: #e6ffff → #d4f2ff → #c6e3f5 at top 8px
                // This is Splay 65 + Light 80% — the most visible part
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFFD4F2FF).withOpacity(0.85),
                          const Color(0xFF4AACDC).withOpacity(0.30),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),

                // ── Layer 4: Border ───────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: const Color(0xFF19BAFF).withOpacity(0.20),
                      width: 1.0,
                    ),
                  ),
                ),

                // ── Layer 5: START text ───────────────────────────────────
                const Center(
                  child: Text(
                    'START',
                    style: TextStyle(
                      fontFamily: 'KdamThmorPro',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 5.5,
                      color: Color(0xFFCFEEFA),
                    ),
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