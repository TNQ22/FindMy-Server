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

    if (activeTagLocations.isNotEmpty) {
      if (activeTagLocations.length == 1) {
        // Only 1 tag: zoom in comfortably (zoom 17.0) so surrounding context is clear
        _mapController.move(activeTagLocations.first, 17.0);
      } else {
        // Multiple tags: fit all active tags across any distance without artificial minZoom clamp
        _mapController.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(activeTagLocations),
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 64),
            maxZoom: 17.0,
            minZoom: 2.0));
      }
    } else if (hereLocation != null) {
      _mapController.move(hereLocation, 17.0);
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

        final List<ZoneItem> visibleZones = zoneRegistry.showZonesOnMap
            ? zoneRegistry.zones.where((z) => z.isActive).toList()
            : (zoneRegistry.highlightedZone != null ? [zoneRegistry.highlightedZone!] : <ZoneItem>[]);

        // Zoom map to fit all accessories and frontend device location ONLY once on initial load
        if (!_hasFittedInitialContent &&
            (accessories.any((a) => a.isActive && a.lastLocation != null) || locationModel.here != null)) {
          _hasFittedInitialContent = true;
          fitToContent(accessories, locationModel.here);
        }

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
                  maxZoom: 21.0,
                  minZoom: 2.0,
                  initialZoom: 13.0,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  interactionOptions: const InteractionOptions(
                      enableMultiFingerGestureRace: true,
                      flags: InteractiveFlag.pinchZoom |
                          InteractiveFlag.drag |
                          InteractiveFlag.doubleTapZoom |
                          InteractiveFlag.scrollWheelZoom |
                          InteractiveFlag.flingAnimation |
                          InteractiveFlag.pinchMove |
                          InteractiveFlag.pinchZoom)),
              children: [
                TileLayer(
                  tileProvider: NetworkTileProvider(),
                  urlTemplate: 'https://{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}&scale=2&hl=$langCode',
                  subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                  maxZoom: 21,
                  maxNativeZoom: 20,
                  userAgentPackageName: 'de.dchristl.headlesshaystack',
                ),

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
                              color: Colors.teal.withOpacity(0.20),
                              borderColor: Colors.teal.shade600,
                              borderStrokeWidth: 2.2,
                            ))
                        .toList(),
                  ),

                // Safe Zones Center Badge Markers
                if (visibleZones.isNotEmpty)
                  MarkerLayer(
                    markers: visibleZones
                        .map<Marker>((z) => Marker(
                              width: 140,
                              height: 32,
                              point: z.center,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade900.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.tealAccent, width: 1),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        z.shapeType == 'polygon' ? Icons.polyline : Icons.shield,
                                        size: 12,
                                        color: Colors.tealAccent,
                                      ),
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
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),

                // Accessories Markers Layer
                MarkerLayer(
                  markers: [
                    ...accessories
                        .where((accessory) => accessory.isActive)
                        .where((accessory) => accessory.lastLocation != null)
                        .map((accessory) => Marker(
                              rotate: true,
                              width: 50,
                              height: 50,
                              point: accessory.lastLocation!,
                              child: AccessoryIcon(
                                  icon: accessory.icon, color: accessory.color),
                            )),
                  ],
                ),

                // Current Device Location Marker
                MarkerLayer(markers: [
                  if (locationModel.here != null)
                    Marker(
                      width: 25.0,
                      height: 25.0,
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

            // Floating Controls
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'safeZonesBtn',
                    tooltip: 'Khu vực cảnh báo (Safe Zones)',
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
                  const SizedBox(height: 8),
                  if (locationModel.here != null)
                    FloatingActionButton.small(
                      heroTag: 'myDeviceLocationBtn',
                      tooltip: 'Vị trí thiết bị của bạn',
                      backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                      foregroundColor: Colors.teal,
                      onPressed: () {
                        _mapController.move(locationModel.here!, 17);
                      },
                      child: const Icon(Icons.my_location, size: 20),
                    ),
                  if (locationModel.here != null) const SizedBox(height: 8),
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

