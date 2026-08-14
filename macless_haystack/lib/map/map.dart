import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:macless_haystack/accessory/accessory_icon.dart';
import 'package:macless_haystack/accessory/accessory_model.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/location/location_model.dart';
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
  bool _hasFittedInitialContent = false;

  @override
  void initState() {
    super.initState();
    _mapController = widget.mapController ?? MapController();

    var accessoryRegistry =
        Provider.of<AccessoryRegistry>(context, listen: false);
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
    await Future.delayed(const Duration(milliseconds: 300));

    List<LatLng> points = [
      ...accessories
          .where((accessory) => accessory.isActive)
          .where((accessory) => accessory.lastLocation != null)
          .map((accessory) => accessory.lastLocation!),
      if (hereLocation != null) hereLocation,
    ];
    
    if (points.isNotEmpty) {
      if (points.length == 1) {
        _mapController.move(points.first, 18);
      } else {
        _mapController.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(50)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AccessoryRegistry, LocationModel>(builder:
        (BuildContext context, AccessoryRegistry accessoryRegistry,
            LocationModel locationModel, Widget? child) {
      var accessories = accessoryRegistry.accessories;
      
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
                initialCenter: locationModel.here ?? const LatLng(16.4637, 107.5909),
                maxZoom: 18.0,
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
                tileBuilder: (context, child, tile) {
                  var isDark = (Theme.of(context).brightness == Brightness.dark);
                  return isDark
                      ? ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            -1,
                            0,
                            0,
                            0,
                            255,
                            0,
                            -1,
                            0,
                            0,
                            255,
                            0,
                            0,
                            -1,
                            0,
                            255,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ]),
                          child: child,
                        )
                      : child;
                },
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: 'de.dchristl.headlesshaystack',
              ),
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
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locationModel.here != null)
                  FloatingActionButton.small(
                    heroTag: 'myDeviceLocationBtn',
                    tooltip: 'Vị trí thiết bị của bạn',
                    backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                    foregroundColor: Colors.teal,
                    onPressed: () {
                      _mapController.move(locationModel.here!, 18);
                    },
                    child: const Icon(Icons.my_location, size: 20),
                  ),
                if (locationModel.here != null) const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'fitMapBoundsBtn',
                  tooltip: 'Bao quát toàn bộ Thẻ & Vị trí thiết bị',
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
    });
  }
}
