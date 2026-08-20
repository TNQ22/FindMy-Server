import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

const String mapStylePreferenceKey = 'map_style_preference';

enum MapLayerStyle {
  googleHybrid(
    'google_hybrid',
    'Vệ tinh Google',
    'Ảnh vệ tinh nét cao của Google kèm tên đường tiếng Việt',
    Icons.satellite_alt,
  ),
  arcgisHybrid(
    'arcgis_hybrid',
    'Vệ tinh Toàn cầu (ArcGIS)',
    'Ảnh vệ tinh ArcGIS phủ kín biển khơi + Tên đường Google',
    Icons.public,
  ),
  googleRoadmap(
    'google_roadmap',
    'Bản đồ Đường bộ',
    'Bản đồ giao thông Google tiêu chuẩn, rõ ràng, sáng sủa',
    Icons.map_outlined,
  );

  final String id;
  final String label;
  final String description;
  final IconData icon;

  const MapLayerStyle(this.id, this.label, this.description, this.icon);

  static MapLayerStyle get current {
    final stored = Settings.getValue<String>(mapStylePreferenceKey, defaultValue: 'google_hybrid');
    return MapLayerStyle.values.firstWhere(
      (e) => e.id == stored,
      orElse: () => MapLayerStyle.googleHybrid,
    );
  }

  static Future<void> save(MapLayerStyle style) async {
    await Settings.setValue<String>(mapStylePreferenceKey, style.id);
  }
}

/// Builds the appropriate TileLayer(s) according to the selected MapLayerStyle.
List<Widget> buildMapTileLayers(MapLayerStyle style, String langCode) {
  switch (style) {
    case MapLayerStyle.googleHybrid:
      return [
        TileLayer(
          tileProvider: NetworkTileProvider(),
          urlTemplate: 'https://{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}&scale=2&hl=$langCode',
          subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
          maxZoom: 21,
          maxNativeZoom: 20,
          userAgentPackageName: 'de.dchristl.headlesshaystack',
        ),
      ];

    case MapLayerStyle.arcgisHybrid:
      return [
        // Base: ArcGIS World Imagery (Complete global satellite coverage without black ocean tiles)
        TileLayer(
          tileProvider: NetworkTileProvider(),
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          maxZoom: 21,
          maxNativeZoom: 19,
          userAgentPackageName: 'de.dchristl.headlesshaystack',
        ),
        // Overlay: Google Transparent Roads & Place Labels
        TileLayer(
          tileProvider: NetworkTileProvider(),
          urlTemplate: 'https://{s}.google.com/vt/lyrs=h&x={x}&y={y}&z={z}&scale=2&hl=$langCode',
          subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
          maxZoom: 21,
          maxNativeZoom: 20,
          userAgentPackageName: 'de.dchristl.headlesshaystack',
        ),
      ];

    case MapLayerStyle.googleRoadmap:
      return [
        TileLayer(
          tileProvider: NetworkTileProvider(),
          urlTemplate: 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&scale=2&hl=$langCode',
          subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
          maxZoom: 21,
          maxNativeZoom: 20,
          userAgentPackageName: 'de.dchristl.headlesshaystack',
        ),
      ];
  }
}

/// Shows a dialog / bottom sheet allowing the user to select one of the 3 map styles.
Future<MapLayerStyle?> showMapStyleSelectorDialog(
  BuildContext context, {
  required MapLayerStyle currentStyle,
  required ValueChanged<MapLayerStyle> onStyleChanged,
}) async {
  return showModalBottomSheet<MapLayerStyle>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900 : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.layers, color: Colors.teal, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Kiểu hiển thị bản đồ',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...MapLayerStyle.values.map((style) {
                  final isSelected = style == currentStyle;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        await MapLayerStyle.save(style);
                        onStyleChanged(style);
                        if (ctx.mounted) Navigator.pop(ctx, style);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.teal.withOpacity(0.12)
                              : (isDark ? Colors.grey.shade800.withOpacity(0.4) : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? Colors.teal : Colors.transparent,
                            width: 1.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.teal : Colors.grey.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                style.icon,
                                color: isSelected ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    style.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isSelected ? Colors.teal : null,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    style.description,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, color: Colors.teal, size: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      );
    },
  );
}
