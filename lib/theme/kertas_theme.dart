import 'package:flutter/material.dart';

/// Sistem Desain KertasPDF sesuai DESIGN.md
/// Dial: ENERGY 2 / RHYTHM 2 / MOTION 1
/// Karakter: Utilitarian & Taktil (Kertas & Tinta, ramah satu tangan)
class KertasColors {
  // Mode Terang (Kertas & Tinta)
  static const Color lightPaperBg = Color(0xFFF6F4EF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFECE8DF);
  static const Color lightBorder = Color(0xFFDCD8CE);
  static const Color lightInk = Color(0xFF141413);
  static const Color lightGraphite = Color(0xFF52504C);

  // Mode Gelap (Meja Kerja Malam)
  static const Color darkSlateBg = Color(0xFF121316);
  static const Color darkSurface = Color(0xFF1C1E24);
  static const Color darkSurfaceAlt = Color(0xFF252830);
  static const Color darkBorder = Color(0xFF2E323B);
  static const Color darkPaperText = Color(0xFFF3F1EC);
  static const Color darkAshText = Color(0xFFA6A49E);

  // Aksen Utama & Status Fungsional
  static const Color vermilion = Color(0xFFD9381E);
  static const Color vermilionStamp = vermilion;
  static const Color vermilionDark = Color(0xFFEA4B30);
  static const Color successGreen = Color(0xFF1B7A43);
  static const Color warningAmber = Color(0xFFB45309);
  static const Color dangerRed = Color(0xFFB91C1C);
}

class KertasTheme {
  static const List<FontFeature> tabularNums = [FontFeature.tabularFigures()];

  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: KertasColors.vermilion,
      onPrimary: Colors.white,
      secondary: KertasColors.lightInk,
      onSecondary: Colors.white,
      surface: KertasColors.lightSurface,
      onSurface: KertasColors.lightInk,
      error: KertasColors.dangerRed,
      onError: Colors.white,
      outline: KertasColors.lightBorder,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBg: KertasColors.lightPaperBg,
      surfaceAlt: KertasColors.lightSurfaceAlt,
      secondaryText: KertasColors.lightGraphite,
      borderColor: KertasColors.lightBorder,
      isDark: false,
    );
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: KertasColors.vermilionDark,
      onPrimary: Colors.white,
      secondary: KertasColors.darkPaperText,
      onSecondary: KertasColors.darkSlateBg,
      surface: KertasColors.darkSurface,
      onSurface: KertasColors.darkPaperText,
      error: Color(0xFFEF4444),
      onError: Colors.white,
      outline: KertasColors.darkBorder,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBg: KertasColors.darkSlateBg,
      surfaceAlt: KertasColors.darkSurfaceAlt,
      secondaryText: KertasColors.darkAshText,
      borderColor: KertasColors.darkBorder,
      isDark: true,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBg,
    required Color surfaceAlt,
    required Color secondaryText,
    required Color borderColor,
    required bool isDark,
  }) {
    final baseText = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      canvasColor: scaffoldBg,
      dividerColor: borderColor,
      focusColor: colorScheme.primary.withValues(alpha: 0.22),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          backgroundColor: colorScheme.surface,
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          side: BorderSide(color: borderColor, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        labelStyle: TextStyle(color: secondaryText, fontSize: 14),
        hintStyle: TextStyle(color: secondaryText, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF282B33) : KertasColors.lightInk,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      textTheme: baseText.copyWith(
        headlineSmall: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        bodyMedium: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 14,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          color: secondaryText,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}

/// Logo KertasPDF (R-23):
/// Lembaran kertas geometris dengan sudut kanan atas terlipat
/// dan garis pindai horizontal merah-oranye tegas (#D9381E).
class KertasLogoMark extends StatelessWidget {
  final double size;

  const KertasLogoMark({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _KertasLogoPainter(isDark: isDark),
      ),
    );
  }
}

class _KertasLogoPainter extends CustomPainter {
  final bool isDark;

  _KertasLogoPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fold = w * 0.28;

    final paperPath = Path()
      ..moveTo(w * 0.14, h * 0.08)
      ..lineTo(w * 0.86 - fold, h * 0.08)
      ..lineTo(w * 0.86, h * 0.08 + fold)
      ..lineTo(w * 0.86, h * 0.92)
      ..lineTo(w * 0.14, h * 0.92)
      ..close();

    final paperFill = Paint()
      ..color = isDark ? const Color(0xFFF3F1EC) : const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;

    final paperStroke = Paint()
      ..color = isDark ? const Color(0xFF141413) : const Color(0xFF141413)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(paperPath, paperFill);
    canvas.drawPath(paperPath, paperStroke);

    // Lipatan sudut kanan atas
    final foldPath = Path()
      ..moveTo(w * 0.86 - fold, h * 0.08)
      ..lineTo(w * 0.86 - fold, h * 0.08 + fold)
      ..lineTo(w * 0.86, h * 0.08 + fold)
      ..close();

    final foldFill = Paint()
      ..color = const Color(0xFFDCD8CE)
      ..style = PaintingStyle.fill;

    canvas.drawPath(foldPath, foldFill);
    canvas.drawPath(foldPath, paperStroke);

    // Garis teks di atas kertas
    final textLinePaint = Paint()
      ..color = const Color(0xFF52504C)
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.28, h * 0.36),
      Offset(w * 0.56, h * 0.36),
      textLinePaint,
    );
    canvas.drawLine(
      Offset(w * 0.28, h * 0.72),
      Offset(w * 0.68, h * 0.72),
      textLinePaint,
    );

    // Garis pindai horizontal merah-oranye tegas (#D9381E)
    final scanLinePaint = Paint()
      ..color = KertasColors.vermilion
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.06, h * 0.54),
      Offset(w * 0.94, h * 0.54),
      scanLinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _KertasLogoPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
