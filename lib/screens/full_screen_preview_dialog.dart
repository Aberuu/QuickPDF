import 'package:flutter/material.dart';
import '../models/pdf_models.dart';
import '../theme/kertas_theme.dart';

/// Mode Pratinjau Layar Penuh dengan Pinch-to-Zoom (Fase 2: Lihat Halaman Besar)
class FullScreenPreviewDialog extends StatefulWidget {
  final List<ScannedPageItem> pages;
  final int initialIndex;
  final ValueChanged<int> onRotatePage;
  final ValueChanged<int> onOpenSmartScanner;

  const FullScreenPreviewDialog({
    super.key,
    required this.pages,
    required this.initialIndex,
    required this.onRotatePage,
    required this.onOpenSmartScanner,
  });

  @override
  State<FullScreenPreviewDialog> createState() =>
      _FullScreenPreviewDialogState();
}

class _FullScreenPreviewDialogState extends State<FullScreenPreviewDialog> {
  late int _currentIndex;
  final TransformationController _zoomController = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.pages.length - 1);
  }

  @override
  void dispose() {
    _zoomController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
  }

  void _goToPage(int newIdx) {
    if (newIdx < 0 || newIdx >= widget.pages.length) return;
    _resetZoom();
    setState(() => _currentIndex = newIdx);
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pages[_currentIndex];
    final pageNo = (_currentIndex + 1).toString().padLeft(2, '0');
    final totalNo = widget.pages.length.toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: const Color(0xFF121316),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121316),
        foregroundColor: const Color(0xFFF3F1EC),
        leading: IconButton(
          tooltip: 'Tutup Pratinjau',
          icon: const Icon(Icons.close, color: Color(0xFFF3F1EC)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Halaman $pageNo / $totalNo  (${page.sourceLabel})',
          style: const TextStyle(
            color: Color(0xFFF3F1EC),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFeatures: KertasTheme.tabularNums,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Reset Perbesaran (Zoom 100%)',
            icon: const Icon(Icons.zoom_out_map, color: Color(0xFFF3F1EC)),
            onPressed: _resetZoom,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFF1C1E24),
              child: const Text(
                'Cubit layar atau gulir untuk memperbesar hingga 4.5x guna memeriksa keterbacaan teks.',
                style: TextStyle(color: Color(0xFFA6A49E), fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                transformationController: _zoomController,
                minScale: 1.0,
                maxScale: 4.5,
                panEnabled: true,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Image.memory(
                      page.displayBytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1C1E24),
                border: Border(top: BorderSide(color: Color(0xFF2E323B))),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Halaman Sebelumnya',
                    onPressed: _currentIndex > 0
                        ? () => _goToPage(_currentIndex - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF252830),
                        side: const BorderSide(color: Color(0xFF3E424D)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onRotatePage(_currentIndex);
                      },
                      icon: const Icon(Icons.rotate_90_degrees_cw_outlined, size: 17),
                      label: const Text('Putar 90°', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onOpenSmartScanner(_currentIndex);
                      },
                      icon: const Icon(Icons.crop_rotate, size: 17),
                      label: const Text('Rapikan', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Halaman Berikutnya',
                    onPressed: _currentIndex < widget.pages.length - 1
                        ? () => _goToPage(_currentIndex + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
