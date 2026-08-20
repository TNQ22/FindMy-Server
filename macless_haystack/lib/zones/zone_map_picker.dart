import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:macless_haystack/dashboard/app_toast.dart';
import 'package:macless_haystack/map/map_tile_layer.dart';
import 'package:provider/provider.dart';

import 'package:macless_haystack/accessory/accessory_icon.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/location/location_model.dart';

class ZoneMapPickerResult {
  final LatLng location;
  final double radius;
  final String shapeType; // "circle" or "polygon"
  final List<LatLng> polygonPoints;

  ZoneMapPickerResult({
    required this.location,
    required this.radius,
    this.shapeType = 'circle',
    this.polygonPoints = const [],
  });
}

class ZoneMapPicker extends StatefulWidget {
  final LatLng? initialLocation;
  final double initialRadius;
  final String initialShapeType;
  final List<LatLng> initialPolygonPoints;

  const ZoneMapPicker({
    super.key,
    this.initialLocation,
    this.initialRadius = 100.0,
    this.initialShapeType = 'circle',
    this.initialPolygonPoints = const [],
  });

  @override
  State<ZoneMapPicker> createState() => _ZoneMapPickerState();
}

class _ZoneMapPickerState extends State<ZoneMapPicker> {
  late MapController _mapController;
  late String _shapeType; // "circle" or "polygon"

  // Circle mode state
  late LatLng _selectedLocation;
  late double _selectedRadius;
  MapLayerStyle _mapStyle = MapLayerStyle.current;

  // Polygon mode state
  late List<LatLng> _polygonPoints;
  late bool _isPolygonClosed;
  bool _isHoveringEdge = false;

  // Dragging state to disable map pan conflict
  bool _isDragging = false;
  Offset? _pointerDownPos;

  final List<double> _presetRadiuses = [50, 100, 200, 500, 1000, 2000, 5000];
  final Distance _distance = const Distance();

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _shapeType = widget.initialShapeType;
    _selectedRadius = widget.initialRadius;
    _polygonPoints = List<LatLng>.from(widget.initialPolygonPoints);
    _isPolygonClosed = _polygonPoints.length >= 3;

    final locationModel = Provider.of<LocationModel>(context, listen: false);
    final accessories = Provider.of<AccessoryRegistry>(context, listen: false).accessories;

    // Determine initial center
    if (widget.initialLocation != null) {
      _selectedLocation = widget.initialLocation!;
    } else if (_polygonPoints.isNotEmpty) {
      _selectedLocation = _computeCentroid(_polygonPoints);
    } else if (locationModel.here != null) {
      _selectedLocation = locationModel.here!;
    } else if (accessories.any((a) => a.lastLocation != null)) {
      _selectedLocation = accessories.firstWhere((a) => a.lastLocation != null).lastLocation!;
    } else {
      _selectedLocation = const LatLng(21.0285, 105.8542); // Default Hanoi center
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLng _computeCentroid(List<LatLng> points) {
    if (points.isEmpty) return _selectedLocation;
    double latSum = 0;
    double lonSum = 0;
    for (final p in points) {
      latSum += p.latitude;
      lonSum += p.longitude;
    }
    return LatLng(latSum / points.length, lonSum / points.length);
  }

  LatLng _movePointByScreenDelta(LatLng latLng, Offset delta) {
    try {
      final zoom = _mapController.camera.zoom;
      final latRad = latLng.latitude * (math.pi / 180.0);
      final cosLat = math.cos(latRad).abs().clamp(0.001, 1.0);

      // Web Mercator exact degrees per pixel: 360 / (256 * 2^zoom) = 1.40625 / 2^zoom
      final degPerPixelX = 1.40625 / math.pow(2, zoom);
      final degPerPixelY = (1.40625 * cosLat) / math.pow(2, zoom);

      final newLat = latLng.latitude - (delta.dy * degPerPixelY);
      final newLon = latLng.longitude + (delta.dx * degPerPixelX);

      return LatLng(
        newLat.clamp(-85.0, 85.0),
        newLon.clamp(-180.0, 180.0),
      );
    } catch (_) {
      return latLng;
    }
  }

  _EdgeHitResult? _findClosestEdge(LatLng tapPoint, {double maxPixels = 28.0}) {
    if (_polygonPoints.length < 2) return null;

    final zoom = _mapController.camera.zoom;
    final latRad = tapPoint.latitude * (math.pi / 180.0);
    final cosLat = math.cos(latRad).abs().clamp(0.001, 1.0);
    final metersPerPixel = (156543.03392 * cosLat) / math.pow(2, zoom);
    final maxToleranceMeters = maxPixels * metersPerPixel;

    int? bestIndex;
    LatLng? bestSnappedPoint;
    double minDistance = double.infinity;

    // If closed: check all segments including last -> first.
    // If open: check consecutive segments 0->1, 1->2, ..., (N-2)->(N-1).
    final numSegments = _isPolygonClosed ? _polygonPoints.length : (_polygonPoints.length - 1);

    for (int i = 0; i < numSegments; i++) {
      final p1 = _polygonPoints[i];
      final p2 = _polygonPoints[(i + 1) % _polygonPoints.length];

      final res = _projectOntoSegment(tapPoint, p1, p2, cosLat);
      if (res.distance < minDistance && res.distance <= maxToleranceMeters) {
        minDistance = res.distance;
        bestIndex = i;
        bestSnappedPoint = res.snappedPoint;
      }
    }

    if (bestIndex != null && bestSnappedPoint != null) {
      return _EdgeHitResult(
        index: bestIndex,
        snappedPoint: bestSnappedPoint,
        distanceMeters: minDistance,
      );
    }
    return null;
  }

  _SegmentProjection _projectOntoSegment(LatLng p, LatLng a, LatLng b, double cosLat) {
    final dx = (b.longitude - a.longitude) * cosLat;
    final dy = b.latitude - a.latitude;
    final segLenSq = dx * dx + dy * dy;

    if (segLenSq < 1e-12) {
      final dist = _distance.as(LengthUnit.Meter, p, a);
      return _SegmentProjection(distance: dist, snappedPoint: a);
    }

    final px = (p.longitude - a.longitude) * cosLat;
    final py = p.latitude - a.latitude;

    final t = ((px * dx + py * dy) / segLenSq).clamp(0.0, 1.0);
    final projLat = a.latitude + t * (b.latitude - a.latitude);
    final projLon = a.longitude + t * (b.longitude - a.longitude);
    final projPoint = LatLng(projLat, projLon);

    final dist = _distance.as(LengthUnit.Meter, p, projPoint);
    return _SegmentProjection(distance: dist, snappedPoint: projPoint);
  }

  void _onMapTapped(TapPosition tapPosition, LatLng point) {
    if (_isDragging) return;
    setState(() {
      if (_shapeType == 'circle') {
        _selectedLocation = point;
      } else {
        // In Polygon mode:
        // 1. If not closed yet, check if tapping near Point #1 to close polygon (when >= 3 points)
        if (!_isPolygonClosed && _polygonPoints.length >= 3) {
          final first = _polygonPoints.first;
          final zoom = _mapController.camera.zoom;
          final latRad = first.latitude * (math.pi / 180.0);
          final cosLat = math.cos(latRad).abs().clamp(0.001, 1.0);
          final metersPerPixel = (156543.03392 * cosLat) / math.pow(2, zoom);
          final distMeters = _distance.as(LengthUnit.Meter, point, first);
          if (distMeters <= (metersPerPixel * 35.0)) {
            _isPolygonClosed = true;
            _selectedLocation = _computeCentroid(_polygonPoints);
            return;
          }
        }

        // 2. Check if tapping near ANY segment/edge (open or closed) -> Snaps & inserts directly onto the line!
        final edgeHit = _findClosestEdge(point, maxPixels: 28.0);
        if (edgeHit != null) {
          _polygonPoints.insert(edgeHit.index + 1, edgeHit.snappedPoint);
          _selectedLocation = _computeCentroid(_polygonPoints);
          return;
        }

        // 3. Otherwise, if not closed, append as new end point
        if (!_isPolygonClosed) {
          _polygonPoints.add(point);
          _selectedLocation = _computeCentroid(_polygonPoints);
        }
      }
    });
  }

  void _undoLastVertex() {
    if (_polygonPoints.isNotEmpty) {
      setState(() {
        if (_isPolygonClosed) {
          _isPolygonClosed = false;
        } else {
          _polygonPoints.removeLast();
          if (_polygonPoints.length < 3) {
            _isPolygonClosed = false;
          }
        }
        if (_polygonPoints.isNotEmpty) {
          _selectedLocation = _computeCentroid(_polygonPoints);
        }
      });
    }
  }

  void _clearPolygon() {
    setState(() {
      _polygonPoints.clear();
      _isPolygonClosed = false;
    });
  }

  void _confirmSelection() {
    if (_shapeType == 'polygon') {
      if (_polygonPoints.length < 3) {
        AppToast.showText(
          context,
          'Vùng đa giác cần tối thiểu 3 điểm. Vui lòng chấm thêm trên bản đồ.',
          icon: Icons.warning_amber_rounded,
          backgroundColor: Colors.amber.shade900,
        );
        return;
      }
      if (!_isPolygonClosed) {
        setState(() => _isPolygonClosed = true);
      }
    }

    final center = _shapeType == 'polygon' && _polygonPoints.isNotEmpty
        ? _computeCentroid(_polygonPoints)
        : _selectedLocation;

    Navigator.pop(
      context,
      ZoneMapPickerResult(
        location: center,
        radius: _selectedRadius,
        shapeType: _shapeType,
        polygonPoints: _polygonPoints,
      ),
    );
  }

  void _showVertexOptions(int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Điểm đỉnh #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Tọa độ: ${_polygonPoints[index].latitude.toStringAsFixed(6)}, ${_polygonPoints[index].longitude.toStringAsFixed(6)}'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Xóa điểm này', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _polygonPoints.removeAt(index);
                  if (_polygonPoints.length < 3) {
                    _isPolygonClosed = false;
                  }
                  if (_polygonPoints.isNotEmpty) {
                    _selectedLocation = _computeCentroid(_polygonPoints);
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final langCode = Localizations.maybeLocaleOf(context)?.languageCode ?? 'vi';
    final locationModel = Provider.of<LocationModel>(context);
    final accessories = Provider.of<AccessoryRegistry>(context).accessories;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final radiusStr = _selectedRadius >= 1000
        ? '${(_selectedRadius / 1000).toStringAsFixed(1)} km'
        : '${_selectedRadius.toInt()} m';

    // ONLY 1 Single Right-Side Handle (East at 90 degrees)
    final LatLng rightSideHandle = _distance.offset(_selectedLocation, _selectedRadius, 90);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn & Vẽ Vùng An Toàn', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                elevation: 1,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.check, size: 18, color: Colors.white),
              label: const Text('Xác nhận', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: _confirmSelection,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // FlutterMap with Precise Crosshair Cursor on Polygon Edge Hover
          MouseRegion(
            cursor: _isHoveringEdge ? SystemMouseCursors.precise : SystemMouseCursors.basic,
            onHover: (event) {
              if (_shapeType != 'polygon' || _polygonPoints.length < 2 || _isDragging) {
                if (_isHoveringEdge) setState(() => _isHoveringEdge = false);
                return;
              }
              try {
                final camera = _mapController.camera;
                final latLng = camera.screenOffsetToLatLng(event.localPosition);
                final edgeHit = _findClosestEdge(latLng, maxPixels: 24.0);
                final isNear = edgeHit != null;
                if (isNear != _isHoveringEdge) {
                  setState(() => _isHoveringEdge = isNear);
                }
              } catch (_) {}
            },
            onExit: (_) {
              if (_isHoveringEdge) setState(() => _isHoveringEdge = false);
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _selectedLocation,
                initialZoom: 16.0,
                maxZoom: 21.0,
                minZoom: 2.0,
                backgroundColor: const Color(0xFF0E2238),
                onTap: _onMapTapped,
                interactionOptions: InteractionOptions(
                  enableMultiFingerGestureRace: true,
                  flags: _isDragging
                      ? (InteractiveFlag.pinchZoom | InteractiveFlag.scrollWheelZoom)
                      : (InteractiveFlag.all),
                ),
              ),
              children: [
                ...buildMapTileLayers(_mapStyle, langCode),

                // Circle Mode Preview Layer
                if (_shapeType == 'circle')
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _selectedLocation,
                        radius: _selectedRadius,
                        useRadiusInMeter: true,
                        color: Colors.teal.withOpacity(0.22),
                        borderColor: Colors.teal.shade600,
                        borderStrokeWidth: 2.5,
                      ),
                    ],
                  ),

                // Polygon Mode: Finalized Closed Polygon Layer
                if (_shapeType == 'polygon' && _isPolygonClosed && _polygonPoints.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _polygonPoints,
                        color: Colors.teal.withOpacity(0.24),
                        borderColor: Colors.teal.shade600,
                        borderStrokeWidth: 2.5,
                      ),
                    ],
                  ),

                // Polygon Mode: Open Drawing Polyline Layer
                if (_shapeType == 'polygon' && !_isPolygonClosed && _polygonPoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _polygonPoints,
                        strokeWidth: 3.0,
                        color: Colors.teal.shade600,
                      ),
                      // Dashed guide line to point 1 when >= 3 points
                      if (_polygonPoints.length >= 3)
                        Polyline(
                          points: [_polygonPoints.last, _polygonPoints.first],
                          strokeWidth: 2.0,
                          color: Colors.teal.shade300.withOpacity(0.7),
                        ),
                    ],
                  ),

                // Existing Accessories Markers for Reference (Clickable to jump & center zone)
                MarkerLayer(
                  markers: [
                    ...accessories
                        .where((accessory) => accessory.isActive && accessory.lastLocation != null)
                        .map((accessory) => Marker(
                              rotate: true,
                              width: 44,
                              height: 44,
                              point: accessory.lastLocation!,
                              child: Tooltip(
                                message: 'Thẻ: ${accessory.name} (Nhấp để dời tâm đến đây)',
                                child: InkWell(
                                  onTap: () {
                                    _mapController.move(accessory.lastLocation!, 17);
                                    if (_shapeType == 'circle') {
                                      setState(() => _selectedLocation = accessory.lastLocation!);
                                    }
                                  },
                                  child: AccessoryIcon(
                                    icon: accessory.icon,
                                    color: accessory.color.withOpacity(0.85),
                                  ),
                                ),
                              ),
                            )),
                  ],
                ),

                // Current Device Location Marker
                if (locationModel.here != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 22.0,
                        height: 22.0,
                        point: locationModel.here!,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).indicatorColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Circle Mode: Center Pin Marker & ONLY 1 Right-Side Drag Handle
                if (_shapeType == 'circle')
                  MarkerLayer(
                    markers: [
                      // Draggable Center Pin
                      Marker(
                        width: 60,
                        height: 60,
                        point: _selectedLocation,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.move,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) {
                              setState(() => _isDragging = true);
                            },
                            onPointerMove: (event) {
                              setState(() {
                                _selectedLocation = _movePointByScreenDelta(_selectedLocation, event.delta);
                              });
                            },
                            onPointerUp: (_) => setState(() => _isDragging = false),
                            onPointerCancel: (_) => setState(() => _isDragging = false),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.teal,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.4),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.shield,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.teal,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ONLY 1 Single Right-Side Handle for Resizing Radius
                      Marker(
                        width: 54,
                        height: 54,
                        point: rightSideHandle,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) {
                              setState(() => _isDragging = true);
                            },
                            onPointerMove: (event) {
                              final zoom = _mapController.camera.zoom;
                              final latRad = _selectedLocation.latitude * (math.pi / 180.0);
                              final cosLat = math.cos(latRad).abs().clamp(0.001, 1.0);
                              final metersPerPixel = (156543.03392 * cosLat) / math.pow(2, zoom);
                              final deltaRadius = event.delta.dx * metersPerPixel;
                              setState(() {
                                _selectedRadius = (_selectedRadius + deltaRadius).clamp(10.0, 10000.0);
                              });
                            },
                            onPointerUp: (_) => setState(() => _isDragging = false),
                            onPointerCancel: (_) => setState(() => _isDragging = false),
                            child: Tooltip(
                              message: 'Kéo sang trái/phải để co/giãn bán kính',
                              child: Container(
                                alignment: Alignment.center,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.teal, width: 3.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.teal.withOpacity(0.6),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.swap_horiz,
                                    color: Colors.teal,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

              // Polygon Mode: Draggable Numbered Vertex Markers (Instant Mouse Drag with Listener)
              if (_shapeType == 'polygon')
                MarkerLayer(
                  markers: [
                    for (int i = 0; i < _polygonPoints.length; i++) ...[
                      () {
                        final isFirstPoint = i == 0;
                        final canCloseOnFirst = isFirstPoint && !_isPolygonClosed && _polygonPoints.length >= 3;

                        return Marker(
                          width: canCloseOnFirst ? 60 : 52,
                          height: canCloseOnFirst ? 60 : 52,
                          point: _polygonPoints[i],
                          child: MouseRegion(
                            cursor: canCloseOnFirst ? SystemMouseCursors.click : SystemMouseCursors.grab,
                            child: Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (event) {
                                _pointerDownPos = event.position;
                                setState(() => _isDragging = true);
                              },
                              onPointerMove: (event) {
                                setState(() {
                                  _polygonPoints[i] = _movePointByScreenDelta(_polygonPoints[i], event.delta);
                                  _selectedLocation = _computeCentroid(_polygonPoints);
                                });
                              },
                              onPointerUp: (event) {
                                final wasClick = _pointerDownPos != null &&
                                    (event.position - _pointerDownPos!).distance < 6;
                                setState(() => _isDragging = false);
                                if (wasClick) {
                                  if (canCloseOnFirst) {
                                    // Click Point #1 when >= 3 points -> close polygon!
                                    setState(() {
                                      _isPolygonClosed = true;
                                      _selectedLocation = _computeCentroid(_polygonPoints);
                                    });
                                  } else {
                                    _showVertexOptions(i);
                                  }
                                }
                              },
                              onPointerCancel: (_) => setState(() => _isDragging = false),
                              child: Tooltip(
                                message: canCloseOnFirst
                                    ? 'Nhấp vào đây để hoàn thành khép kín đa giác'
                                    : 'Điểm đỉnh #${i + 1} (Kéo để dời, nhấp để xóa)',
                                child: Container(
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: canCloseOnFirst ? 40 : 36,
                                    height: canCloseOnFirst ? 40 : 36,
                                    decoration: BoxDecoration(
                                      color: canCloseOnFirst ? Colors.green.shade600 : Colors.teal,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: canCloseOnFirst ? Colors.lightGreenAccent : Colors.white,
                                        width: canCloseOnFirst ? 3.0 : 2.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (canCloseOnFirst ? Colors.green : Colors.teal).withOpacity(0.65),
                                          blurRadius: canCloseOnFirst ? 12 : 8,
                                          spreadRadius: canCloseOnFirst ? 3 : 2,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: canCloseOnFirst
                                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                                          : Text(
                                              '${i + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }(),
                    ],
                  ],
                ),
            ],
          ),
        ),

          // Floating Layer Style Switcher Button (Top-Right)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900.withOpacity(0.95) : Colors.white.withOpacity(0.95),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.layers_outlined, size: 20),
                tooltip: 'Đổi kiểu bản đồ (${_mapStyle.label})',
                color: Colors.teal,
                onPressed: () {
                  showMapStyleSelectorDialog(
                    context,
                    currentStyle: _mapStyle,
                    onStyleChanged: (newStyle) {
                      setState(() => _mapStyle = newStyle);
                    },
                  );
                },
              ),
            ),
          ),

          // Top Mode Switcher & Instruction Bar
          Positioned(
            top: 16,
            left: 16,
            right: 68,
            child: Column(
              children: [
                // Segmented Mode Switcher
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade900.withOpacity(0.95) : Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Circle Option
                      InkWell(
                        borderRadius: BorderRadius.circular(25),
                        onTap: () => setState(() => _shapeType = 'circle'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _shapeType == 'circle' ? Colors.teal : Colors.transparent,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.radio_button_checked,
                                size: 16,
                                color: _shapeType == 'circle' ? Colors.white : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Hình tròn (Circle)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _shapeType == 'circle' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Polygon Option
                      InkWell(
                        borderRadius: BorderRadius.circular(25),
                        onTap: () => setState(() => _shapeType = 'polygon'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _shapeType == 'polygon' ? Colors.teal : Colors.transparent,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.polyline,
                                size: 16,
                                color: _shapeType == 'polygon' ? Colors.white : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Đa giác (Polygon)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _shapeType == 'polygon' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Dynamic Instruction Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _shapeType == 'circle' ? Icons.touch_app : Icons.format_shapes,
                        color: Colors.tealAccent,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _shapeType == 'circle'
                              ? 'Kéo tâm để dời • Kéo nút viền bên phải để co/giãn bán kính'
                              : (_polygonPoints.isEmpty
                                  ? 'Chạm bản đồ để chấm điểm đầu tiên'
                                  : (!_isPolygonClosed
                                      ? (_polygonPoints.length < 3
                                          ? 'Chấm tiếp các góc của đa giác (${_polygonPoints.length}/3)'
                                          : 'Nhấp vào điểm số 1 để khép kín đa giác')
                                      : 'Đã khép kín • Kéo đỉnh để chỉnh • Nhấp bất kỳ đâu trên cạnh để chèn thêm điểm')),
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Floating Tools & Polygon Action Buttons
          Positioned(
            right: 16,
            bottom: 180,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Polygon Close / Re-open action button
                if (_shapeType == 'polygon' && _polygonPoints.length >= 3) ...[
                  if (!_isPolygonClosed)
                    FloatingActionButton.extended(
                      heroTag: 'mapPickerClosePolyBtn',
                      tooltip: 'Hoàn thành khép kín đa giác',
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Khép kín', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        setState(() {
                          _isPolygonClosed = true;
                          _selectedLocation = _computeCentroid(_polygonPoints);
                        });
                      },
                    )
                  else
                    FloatingActionButton.small(
                      heroTag: 'mapPickerReopenPolyBtn',
                      tooltip: 'Mở lại để chấm thêm điểm',
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      onPressed: () {
                        setState(() => _isPolygonClosed = false);
                      },
                      child: const Icon(Icons.edit, size: 18),
                    ),
                  const SizedBox(height: 8),
                ],

                // Polygon Undo Button
                if (_shapeType == 'polygon' && _polygonPoints.isNotEmpty) ...[
                  FloatingActionButton.small(
                    heroTag: 'mapPickerUndoBtn',
                    tooltip: 'Hoàn tác điểm vừa chấm',
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    onPressed: _undoLastVertex,
                    child: const Icon(Icons.undo, size: 20),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'mapPickerClearBtn',
                    tooltip: 'Xóa toàn bộ điểm',
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    onPressed: _clearPolygon,
                    child: const Icon(Icons.delete_sweep, size: 20),
                  ),
                  const SizedBox(height: 8),
                ],

                // Tag List Quick-Jump Button (Chuyển đến vị trí Thẻ định vị)
                if (accessories.any((a) => a.isActive && a.lastLocation != null)) ...[
                  PopupMenuButton<int>(
                    tooltip: 'Chuyển đến vị trí Thẻ định vị',
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.sell_outlined, size: 20, color: Colors.teal),
                    ),
                    onSelected: (idx) {
                      final tag = accessories[idx];
                      if (tag.lastLocation != null) {
                        _mapController.move(tag.lastLocation!, 17);
                        if (_shapeType == 'circle') {
                          setState(() => _selectedLocation = tag.lastLocation!);
                        }
                        AppToast.showText(
                          context,
                          'Đã chuyển vị trí đến thẻ "${tag.name}"',
                          icon: Icons.place,
                          backgroundColor: Colors.teal.shade800,
                          duration: const Duration(seconds: 3),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      for (int i = 0; i < accessories.length; i++)
                        if (accessories[i].isActive && accessories[i].lastLocation != null)
                          PopupMenuItem(
                            value: i,
                            child: Row(
                              children: [
                                Icon(accessories[i].icon, color: accessories[i].color, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    accessories[i].name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Vị trí thiết bị của bạn
                if (locationModel.here != null) ...[
                  FloatingActionButton.small(
                    heroTag: 'mapPickerMyLocBtn',
                    tooltip: 'Vị trí thiết bị của bạn',
                    backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.95),
                    foregroundColor: Colors.teal,
                    onPressed: () {
                      _mapController.move(locationModel.here!, 16);
                      if (_shapeType == 'circle') {
                        setState(() => _selectedLocation = locationModel.here!);
                      }
                    },
                    child: const Icon(Icons.my_location, size: 20),
                  ),
                  const SizedBox(height: 8),
                ],

                FloatingActionButton.small(
                  heroTag: 'mapPickerCenterZoneBtn',
                  tooltip: 'Tâm vùng đang chọn',
                  backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.95),
                  foregroundColor: Colors.teal,
                  onPressed: () {
                    _mapController.move(_selectedLocation, 16);
                  },
                  child: const Icon(Icons.center_focus_strong, size: 20),
                ),
              ],
            ),
          ),

          // Bottom Control Card with Direct Slider & Presets
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900.withOpacity(0.95) : Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.teal.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _shapeType == 'circle' ? Icons.location_on : Icons.polyline,
                          color: Colors.teal,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _shapeType == 'circle' ? 'Tọa độ tâm đang chọn:' : 'Tâm đa giác (${_polygonPoints.length} đỉnh):',
                              style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${_selectedLocation.latitude.toStringAsFixed(6)}, ${_selectedLocation.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      if (_shapeType == 'circle')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.teal.shade900.withOpacity(0.5) : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? Colors.teal.shade700 : Colors.teal.shade200),
                          ),
                          child: Text(
                            'Bán kính: $radiusStr',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.tealAccent : Colors.teal.shade800,
                            ),
                          ),
                        )
                      else
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            if (!_isPolygonClosed && _polygonPoints.length >= 3) {
                              setState(() {
                                _isPolygonClosed = true;
                                _selectedLocation = _computeCentroid(_polygonPoints);
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isPolygonClosed
                                  ? (isDark ? Colors.green.shade900.withOpacity(0.4) : Colors.green.shade50)
                                  : (_polygonPoints.length >= 3
                                      ? (isDark ? Colors.green.shade800.withOpacity(0.6) : Colors.green.shade100)
                                      : (isDark ? Colors.orange.shade900.withOpacity(0.4) : Colors.orange.shade50)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _isPolygonClosed
                                    ? (isDark ? Colors.green.shade700 : Colors.green.shade300)
                                    : (_polygonPoints.length >= 3
                                        ? (isDark ? Colors.green.shade600 : Colors.green.shade600)
                                        : (isDark ? Colors.orange.shade700 : Colors.orange.shade300)),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isPolygonClosed ? Icons.check_circle : Icons.radio_button_unchecked,
                                  size: 14,
                                  color: _isPolygonClosed
                                      ? (isDark ? Colors.greenAccent : Colors.green.shade800)
                                      : (isDark ? Colors.orangeAccent : Colors.orange.shade800),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isPolygonClosed
                                      ? 'Đã khép kín'
                                      : (_polygonPoints.length >= 3 ? 'Nhấp để khép kín' : 'Chưa khép kín'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _isPolygonClosed
                                        ? (isDark ? Colors.greenAccent : Colors.green.shade800)
                                        : (_polygonPoints.length >= 3
                                            ? (isDark ? Colors.greenAccent : Colors.green.shade900)
                                            : (isDark ? Colors.orangeAccent : Colors.orange.shade800)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Circle mode: Direct Slider & Preset radius chips
                  if (_shapeType == 'circle') ...[
                    Slider(
                      value: _selectedRadius,
                      min: 30,
                      max: 5000,
                      divisions: 100,
                      activeColor: Colors.teal,
                      inactiveColor: isDark ? Colors.grey.shade700 : Colors.teal.shade100,
                      onChanged: (val) => setState(() => _selectedRadius = val),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _presetRadiuses.map((r) {
                          final isSel = (_selectedRadius - r).abs() < 5;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                r >= 1000 ? '${(r / 1000).toInt()}km' : '${r.toInt()}m',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                  color: isSel
                                      ? (isDark ? Colors.white : Colors.teal.shade900)
                                      : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                                ),
                              ),
                              selected: isSel,
                              selectedColor: isDark ? Colors.teal.shade700 : Colors.teal.shade100,
                              backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                              side: BorderSide(
                                color: isSel ? Colors.teal : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                              ),
                              onSelected: (_) => setState(() => _selectedRadius = r),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EdgeHitResult {
  final int index;
  final LatLng snappedPoint;
  final double distanceMeters;

  _EdgeHitResult({
    required this.index,
    required this.snappedPoint,
    required this.distanceMeters,
  });
}

class _SegmentProjection {
  final double distance;
  final LatLng snappedPoint;

  _SegmentProjection({
    required this.distance,
    required this.snappedPoint,
  });
}
