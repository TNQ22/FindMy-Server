import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:macless_haystack/accessory/accessory_icon.dart';
import 'package:macless_haystack/accessory/accessory_model.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/location/location_model.dart';
import 'package:macless_haystack/zones/zone_model.dart';
import 'package:macless_haystack/zones/zone_registry.dart';
import 'package:macless_haystack/zones/zone_management_dialog.dart';
import 'package:macless_haystack/map/map_tile_layer.dart';
import 'package:provider/provider.dart';

class AccessoryMap extends StatefulWidget {
  final MapController? mapController;

  /// Displays a map with all accessories at their latest position.
  const AccessoryMap({
    super.key,
    this.mapController,
  });

  @override
  State<StatefulWidget> createState() {
    return _AccessoryMapState();
  }
}

class _AccessoryMapState extends State<AccessoryMap> {
  late MapController _mapController;
  void Function()? cancelLocationUpdates;
  void Function()? cancelAccessoryUpdates;
  static bool _hasFittedInitialContent = false;
  MapLayerStyle _mapStyle = MapLayerStyle.current;

  @override
  void initState() {
    super.initState();
    _mapController = widget.mapController ?? MapController();

    var locationModel = Provider.of<LocationModel>(context, listen: false);

    void listener() {
      if (mounted) {
        setState(() {});
      }
    }

    locationModel.addListener(listener);
    cancelLocationUpdates = () => locationModel.removeListener(listener);
  }

  @override
  void dispose() {
    super.dispose();

    cancelLocationUpdates?.call();
    cancelAccessoryUpdates?.call();
  }

  void fitToContent(List<Accessory> accessories, LatLng? hereLocation) async {
    // Delay to prevent race conditions
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final activeTagLocations = accessories
        .where((accessory) => accessory.isActive && accessory.lastLocation != null)
        .map((accessory) => accessory.lastLocation!)
        .toList();

    final isDesktop = MediaQuery.of(context).size.width >= 720;
    final insets = EdgeInsets.fromLTRB(
      isDesktop ? 466 : 35,
      isDesktop ? 70 : 35,
      isDesktop ? 127 : 92,
      isDesktop ? 70 : 35,
    );

    if (activeTagLocations.isNotEmpty) {
      if (activeTagLocations.length == 1) {
        // Only 1 tag: center in visible area with proper padding
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([activeTagLocations.first]),
          maxZoom: 16.5,
          padding: insets,
        ));
      } else {
        // Multiple tags: fit all active tags with generous insets
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(activeTagLocations),
          padding: insets,
          maxZoom: 17.0,
          minZoom: 2.0,
        ));
      }
    } else if (hereLocation != null) {
      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([hereLocation]),
        maxZoom: 16.5,
        padding: insets,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final langCode = Localizations.maybeLocaleOf(context)?.languageCode ?? 'vi';

    return Consumer3<AccessoryRegistry, LocationModel, ZoneRegistry>(
      builder: (BuildContext context, AccessoryRegistry accessoryRegistry,
          LocationModel locationModel, ZoneRegistry zoneRegistry, Widget? child) {
        var accessories = accessoryRegistry.accessories;
        
        // Focus zone requested by user
        if (zoneRegistry.focusedZone != null) {
          final fz = zoneRegistry.focusedZone!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mapController.move(fz.center, 16);
            zoneRegistry.clearFocusedCamera();
          });
        }

        // Auto-fit to active accessories upon initial load
        if (!_hasFittedInitialContent &&
            accessoryRegistry.initialLoadFinished &&
            accessories.isNotEmpty) {
          _hasFittedInitialContent = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            fitToContent(accessories, locationModel.here);
          });
        }

        final List<ZoneItem> visibleZones = zoneRegistry.showZonesOnMap
            ? zoneRegistry.zones.where((z) => z.isActive).toList()
            : (zoneRegistry.highlightedZone != null ? [zoneRegistry.highlightedZone!] : <ZoneItem>[]);

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                  onTap: (_, __) {
                    if (zoneRegistry.highlightedZone != null && !zoneRegistry.showZonesOnMap) {
                      zoneRegistry.clearHighlightedZone();
                    }
                  },
                  initialCenter: locationModel.here ?? const LatLng(16.4637, 107.5909),
                  initialZoom: 13,
                  maxZoom: 21,
                  minZoom: 2,
                  backgroundColor: const Color(0xFF0E2238),
                  interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom |
                          InteractiveFlag.drag |
                          InteractiveFlag.doubleTapZoom |
                          InteractiveFlag.scrollWheelZoom |
                          InteractiveFlag.flingAnimation |
                          InteractiveFlag.pinchMove |
                          InteractiveFlag.pinchZoom),
                ),
              children: [
                ...buildMapTileLayers(_mapStyle, langCode),

                // Safe Zones Circle Layer (Circle Zones)
                if (visibleZones.isNotEmpty)
                  CircleLayer(
                    circles: visibleZones
                        .where((z) => z.shapeType != 'polygon')
                        .map<CircleMarker>((z) => CircleMarker(
                              point: z.center,
                              radius: z.radius,
                              useRadiusInMeter: true,
                              color: Colors.teal.withOpacity(0.18),
                              borderColor: Colors.teal.shade600,
                              borderStrokeWidth: 2.0,
                            ))
                        .toList(),
                  ),

                // Safe Zones Polygon Layer (Polygon Zones)
                if (visibleZones.isNotEmpty)
                  PolygonLayer(
                    polygons: visibleZones
                        .where((z) => z.shapeType == 'polygon' && z.polygonPoints.length >= 3)
                        .map<Polygon>((z) => Polygon(
                              points: z.polygonPoints,
                              color: Colors.teal.withOpacity(0.18),
                              borderColor: Colors.teal.shade600,
                              borderStrokeWidth: 2.0,
                            ))
                        .toList(),
                  ),

                // Safe Zones Label/Badge Layer
                if (visibleZones.isNotEmpty)
                  MarkerLayer(
                    markers: visibleZones.map<Marker>((z) {
                      return Marker(
                        point: z.center,
                        width: 140,
                        height: 36,
                        alignment: Alignment.center,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade800.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white, width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.35),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.shield, color: Colors.white, size: 12),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      z.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                // Accessories Markers Layer
                MarkerLayer(markers: [
                  ...accessories.where((a) => a.isActive).map(
                        (a) => a.lastLocation != null
                            ? Marker(
                                width: 40,
                                height: 40,
                                point: a.lastLocation!,
                                child: Stack(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surface,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.center,
                                      child: AccessoryIcon(
                                        icon: a.icon,
                                        color: a.color,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const Marker(
                                point: LatLng(0, 0),
                                child: SizedBox(),
                              ),
                      ),
                  if (locationModel.here != null)
                    Marker(
                      width: 20,
                      height: 20,
                      point: locationModel.here!,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(5),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).indicatorColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ]),
              ],
            ),

            // Floating Controls: Clean Vertical Column with FAB buttons
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'safeZonesBtn',
                    tooltip: 'Khu vực cảnh báo',
                    backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                    foregroundColor: Colors.teal,
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => const ZoneManagementDialog(),
                      );
                    },
                    child: const Icon(Icons.shield_outlined, size: 20),
                  ),
                  const SizedBox(height: 4),
                  FloatingActionButton.small(
                    heroTag: 'mapStyleBtn',
                    tooltip: 'Đổi kiểu bản đồ (${_mapStyle.label})',
                    backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                    foregroundColor: Colors.teal,
                    onPressed: () {
                      showMapStyleSelectorDialog(
                        context,
                        currentStyle: _mapStyle,
                        onStyleChanged: (newStyle) {
                          setState(() => _mapStyle = newStyle);
                        },
                      );
                    },
                    child: const Icon(Icons.layers_outlined, size: 20),
                  ),
                  const SizedBox(height: 4),
                  if (locationModel.here != null) ...[
                    FloatingActionButton.small(
                      heroTag: 'myDeviceLocationBtn',
                      tooltip: 'Vị trí thiết bị của bạn',
                      backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                      foregroundColor: Colors.teal,
                      onPressed: () {
                        final isDesk = MediaQuery.of(context).size.width >= 720;
                        _mapController.fitCamera(
                          CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints([locationModel.here!]),
                            maxZoom: 17.0,
                            padding: EdgeInsets.fromLTRB(
                              isDesk ? 466 : 35,
                              isDesk ? 70 : 35,
                              isDesk ? 127 : 92,
                              isDesk ? 70 : 35,
                            ),
                          ),
                        );
                      },
                      child: const Icon(Icons.my_location, size: 20),
                    ),
                    const SizedBox(height: 4),
                  ],
                  FloatingActionButton.small(
                    heroTag: 'fitMapBoundsBtn',
                    tooltip: 'Bao quát toàn bộ Thẻ định vị',
                    backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    onPressed: () {
                      fitToContent(accessories, locationModel.here);
                    },
                    child: const Icon(Icons.crop_free, size: 20),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

