import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/pdf_models.dart';
import '../theme/kertas_theme.dart';

/// Overlay animasi tangkapan layar bergaya iOS (iPhone Screenshot Style):
/// 1. Kilatan putih singkat (80ms)
/// 2. Pratinjau lembaran dokumen hasil potong melayang mengecil (350ms, easeOutCubic)
///    menuju tumpukan thumbnail di pojok kiri bawah layar.
class ScreenshotCaptureAnimationOverlay extends StatefulWidget {
  final Uint8List? animatingImageBytes;
  final int captureSequenceId;
  final VoidCallback? onAnimationComplete;

  const ScreenshotCaptureAnimationOverlay({
    super.key,
    required this.animatingImageBytes,
    required this.captureSequenceId,
    this.onAnimationComplete,
  });

  @override
  State<ScreenshotCaptureAnimationOverlay> createState() =>
      _ScreenshotCaptureAnimationOverlayState();
}

class _ScreenshotCaptureAnimationOverlayState
    extends State<ScreenshotCaptureAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Uint8List? _activeBytes;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (mounted) {
            setState(() {
              _activeBytes = null;
            });
          }
          widget.onAnimationComplete?.call();
        }
      });

    if (widget.animatingImageBytes != null) {
      _activeBytes = widget.animatingImageBytes;
      _triggerAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant ScreenshotCaptureAnimationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.captureSequenceId != oldWidget.captureSequenceId &&
        widget.animatingImageBytes != null) {
      _activeBytes = widget.animatingImageBytes;
      _triggerAnimation();
    }
  }

  void _triggerAnimation() {
    final bool disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _activeBytes = null;
        });
        widget.onAnimationComplete?.call();
      });
      return;
    }
    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _activeBytes;
    if (bytes == null || !_controller.isAnimating) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxW = constraints.maxWidth;
          final double maxH = constraints.maxHeight;

          // Posisi awal: bingkai pratinjau besar di tengah viewfinder
          final double startW = (maxW * 0.72).clamp(180.0, 360.0);
          final double startH = (startW * 1.35).clamp(240.0, maxH * 0.68);
          final Rect startRect = Rect.fromCenter(
            center: Offset(maxW * 0.5, maxH * 0.44),
            width: startW,
            height: startH,
          );

          // Posisi akhir: tumpukan thumbnail di pojok kiri bawah
          final Rect endRect = Rect.fromLTWH(
            20.0,
            (maxH - 104.0).clamp(20.0, maxH),
            60.0,
            80.0,
          );

          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final double t = _controller.value;

              // Fase 1 (0.00 - 0.11 ~ 70ms): kedipan shutter putih lembut seketika
              final double flashOpacity = t < 0.11
                  ? (1.0 - (t / 0.11)).clamp(0.0, 0.45)
                  : 0.0;

              // Fase 2 (0.11 - 1.00 ~ 580ms): kurva easeOutCubic melambat anggun ke pojok kiri bawah
              final double flyProgress = t <= 0.11
                  ? 0.0
                  : Curves.easeOutCubic.transform(((t - 0.11) / 0.89).clamp(0.0, 1.0));

              final Rect currentRect = Rect.lerp(startRect, endRect, flyProgress)!;
              final double cardOpacity = t > 0.92
                  ? ((1.0 - t) / 0.08).clamp(0.0, 1.0)
                  : 1.0;

              return Stack(
                fit: StackFit.expand,
                children: [
                  if (flashOpacity > 0)
                    ColoredBox(
                      color: Colors.white.withValues(alpha: flashOpacity),
                    ),
                  Positioned.fromRect(
                    rect: currentRect,
                    child: Opacity(
                      opacity: cardOpacity,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Tumpukan thumbnail dokumen di pojok kiri bawah kamera (bergaya iOS Screenshot).
/// Menampilkan halaman terakhir yang dipotret dengan lencana jumlah halaman tabular.
class CapturedPagesCornerStack extends StatelessWidget {
  final List<ScannedPageItem> pages;
  final VoidCallback onTapStack;

  const CapturedPagesCornerStack({
    super.key,
    required this.pages,
    required this.onTapStack,
  });

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const SizedBox(width: 68, height: 84);
    }

    final ScannedPageItem latest = pages.last;
    final String badgeText = pages.length.toString().padLeft(2, '0');

    return Semantics(
      button: true,
      label: 'Tumpukan ${pages.length} halaman terpotret. Ketuk untuk meninjau.',
      child: InkWell(
        onTap: onTapStack,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 68,
          height: 84,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Efek tumpukan kertas di belakang jika halaman > 1
              if (pages.length > 1)
                Positioned(
                  left: 6,
                  top: 0,
                  child: Container(
                    width: 56,
                    height: 74,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5DFD3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.75),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

              // Thumbnail halaman terbaru
              Positioned(
                left: 0,
                top: 6,
                child: Container(
                  width: 58,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(
                    latest.displayBytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),

              // Lencana nomor tabular di pojok kanan atas thumbnail
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: KertasColors.vermilionStamp,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: KertasTheme.tabularNums,
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
