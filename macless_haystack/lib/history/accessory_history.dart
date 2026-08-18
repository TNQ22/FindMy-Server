import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:logger/logger.dart';
import 'package:macless_haystack/accessory/accessory_model.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/history/history_date_range_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'dart:math';

class ClusteredHistoryEntry {
  double latitude;
  double longitude;
  final DateTime startTime;
  DateTime endTime;
  int? accuracy;
  String? batteryStatus;
  final List<LocationHistoryEntry> rawEntries;

  ClusteredHistoryEntry({
    required this.latitude,
    required this.longitude,
    required this.startTime,
    required this.endTime,
    this.accuracy,
    this.batteryStatus,
    required this.rawEntries,
  });

  Duration get duration => endTime.difference(startTime);
}

class AccessoryHistory extends StatefulWidget {
  final Accessory accessory;

  /// Shows previous locations of a specific [accessory] on a map.
  /// History is loaded on-demand from the backend API based on the selected date range.
  const AccessoryHistory({
    super.key,
    required this.accessory,
  });

  @override
  State<StatefulWidget> createState() => _AccessoryHistoryState();
}

class _AccessoryHistoryState extends State<AccessoryHistory> {
  late MapController _mapController;
  final logger = Logger(printer: PrettyPrinter(methodCount: 0));

  bool isLoading = false;
  bool isLineLayerVisible = true;
  bool isPointLayerVisible = true;

  bool showPopup = false;
  ClusteredHistoryEntry? popupEntry;

  // The fetched location history entries for the current date range
  List<LocationHistoryEntry> _historyEntries = [];

  // Current date range
  DateTime _fromDate = DateTime.now().subtract(const Duration(hours: 24));
  DateTime _toDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // Default: load last 24 hours
    _loadHistory(_fromDate, _toDate);
  }

  Future<void> _loadHistory(DateTime from, DateTime to) async {
    setState(() {
      isLoading = true;
      _fromDate = from;
      _toDate = to;
      showPopup = false;
      popupEntry = null;
    });

    try {
      final registry =
          Provider.of<AccessoryRegistry>(context, listen: false);
      final fromMs = from.millisecondsSinceEpoch;
      final toMs = to.millisecondsSinceEpoch;

      final entries = await registry.loadDeviceHistory(
        widget.accessory.hashedPublicKey,
        fromTs: fromMs,
        toTs: toMs,
      );

      if (mounted) {
        setState(() {
          _historyEntries = entries;
          isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
      }
    } catch (e) {
      logger.e('Error loading history: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _fitBounds() {
    if (_historyEntries.isNotEmpty) {
      final points =
          _historyEntries.map((e) => LatLng(e.latitude, e.longitude)).toList();
      try {
        final bounds = LatLngBounds.fromPoints(points);
        _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32), maxZoom: 17.0));
      } catch (_) {
        if (_historyEntries.isNotEmpty) {
          _mapController.move(
              LatLng(_historyEntries.last.latitude, _historyEntries.last.longitude), 14.0);
        }
      }
    } else if (widget.accessory.lastLocation != null) {
      _mapController.move(widget.accessory.lastLocation!, 17.0);
    }
  }

  List<ClusteredHistoryEntry> _clusterEntries(List<LocationHistoryEntry> rawEntries) {
    if (rawEntries.isEmpty) return [];

    final sorted = List<LocationHistoryEntry>.from(rawEntries)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final List<ClusteredHistoryEntry> clusters = [];

    for (final entry in sorted) {
      if (clusters.isEmpty) {
        clusters.add(ClusteredHistoryEntry(
          latitude: entry.latitude,
          longitude: entry.longitude,
          startTime: entry.timestamp,
          endTime: entry.timestamp,
          accuracy: entry.accuracy,
          batteryStatus: entry.batteryStatus,
          rawEntries: [entry],
        ));
        continue;
      }

      final lastCluster = clusters.last;
      final latDiff = (lastCluster.latitude - entry.latitude).abs();
      final lonDiff = (lastCluster.longitude - entry.longitude).abs();

      // Group nearby locations within ~100m (0.001 degrees)
      if (latDiff <= 0.001 && lonDiff <= 0.001) {
        lastCluster.endTime = entry.timestamp;
        lastCluster.rawEntries.add(entry);
        lastCluster.latitude = entry.latitude;
        lastCluster.longitude = entry.longitude;
        lastCluster.accuracy = entry.accuracy ?? lastCluster.accuracy;
        if (entry.batteryStatus != null) {
          lastCluster.batteryStatus = entry.batteryStatus;
        }
      } else {
        clusters.add(ClusteredHistoryEntry(
          latitude: entry.latitude,
          longitude: entry.longitude,
          startTime: entry.timestamp,
          endTime: entry.timestamp,
          accuracy: entry.accuracy,
          batteryStatus: entry.batteryStatus,
          rawEntries: [entry],
        ));
      }
    }

    return clusters;
  }

  @override
  Widget build(BuildContext context) {
    final langCode = Localizations.maybeLocaleOf(context)?.languageCode ?? 'vi';
    final entries = _historyEntries;
    final clusters = _clusterEntries(entries);
    final historyLength = min(clusters.length, 255);
    final delta = historyLength > 1 ? (255 ~/ (historyLength - 1)).ceil() : 255;

    List<Polyline> polylines = [];
    int blue = delta;
    for (int i = 0; i < clusters.length - 1; i++) {
      if (isLineLayerVisible) {
        polylines.add(Polyline(
          points: [
            LatLng(clusters[i].latitude, clusters[i].longitude),
            LatLng(clusters[i + 1].latitude, clusters[i + 1].longitude),
          ],
          strokeWidth: 4,
          color: Color.fromRGBO(33, 150, blue.clamp(0, 255), 1),
        ));
      }
      blue = (blue + delta).clamp(0, 255);
    }

    final visibility = [isLineLayerVisible, isPointLayerVisible];

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${widget.accessory.name} (${clusters.length} điểm dừng / ${entries.length} báo cáo)',
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Map
            Flexible(
              flex: 3,
              fit: FlexFit.tight,
              child: FlutterMap(
                key: ValueKey(MediaQuery.of(context).orientation),
                mapController: _mapController,
                options: MapOptions(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  initialCenter: widget.accessory.lastLocation ??
                      const LatLng(16.4637, 107.5909),
                  maxZoom: 21.0,
                  minZoom: 2.0,
                  initialZoom: 13.0,
                  interactionOptions: const InteractionOptions(
                    enableMultiFingerGestureRace: true,
                    flags: InteractiveFlag.pinchZoom |
                        InteractiveFlag.drag |
                        InteractiveFlag.doubleTapZoom |
                        InteractiveFlag.scrollWheelZoom |
                        InteractiveFlag.flingAnimation |
                        InteractiveFlag.pinchMove |
                        InteractiveFlag.pinchZoom,
                  ),
                  onTap: (_, __) {
                    setState(() {
                      showPopup = false;
                      popupEntry = null;
                    });
                  },
                ),
                children: [
                  TileLayer(
                    tileProvider: NetworkTileProvider(),
                    urlTemplate:
                        'https://{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}&scale=2&hl=$langCode',
                    subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                    maxZoom: 21,
                    maxNativeZoom: 20,
                    userAgentPackageName: 'de.dchristl.headlesshaystack',
                    /*tileBuilder: (context, child, tile) {
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      return isDark
                          ? ColorFiltered(
                              colorFilter: const ColorFilter.matrix([
                                -1, 0, 0, 0, 255,
                                0, -1, 0, 0, 255,
                                0, 0, -1, 0, 255,
                                0, 0, 0,  1,   0,
                              ]),
                              child: child,
                            )
                          : child;
                    },*/
                  ),
                  PolylineLayer(polylines: polylines),
                  MarkerLayer(
                    markers: clusters
                        .map((cluster) {
                          final size = _calcSize(cluster);
                          final isSelected = cluster == popupEntry;
                          final dotColor = isSelected ? Colors.red : Theme.of(context).indicatorColor;

                          return Marker(
                            point: LatLng(cluster.latitude, cluster.longitude),
                            width: size + 12,
                            height: size + 12,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  showPopup = true;
                                  popupEntry = cluster;
                                });
                              },
                              child: Center(
                                child: isPointLayerVisible
                                    ? Container(
                                        width: size,
                                        height: size,
                                        decoration: BoxDecoration(
                                          color: dotColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.black,
                                            width: isSelected ? 4.0 : 3.2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.6),
                                              blurRadius: 5,
                                              offset: const Offset(0, 1.5),
                                            ),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          );
                        })
                        .toList(),
                  ),
                  if (showPopup && popupEntry != null)
                    MarkerLayer(
                      markers: [
                        _buildPopupMarker(popupEntry!),
                      ],
                    ),
                  // Layer toggle buttons
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ToggleButtons(
                        isSelected: visibility,
                        onPressed: (int index) {
                          setState(() {
                            visibility[index] = !visibility[index];
                            isLineLayerVisible = visibility[0];
                            isPointLayerVisible = visibility[1];
                            showPopup = false;
                            popupEntry = null;
                          });
                        },
                        children: const [
                          Icon(Icons.timeline),
                          Icon(Icons.scatter_plot_rounded),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Date range picker
            Flexible(
              flex: 0,
              fit: FlexFit.loose,
              child: HistoryDateRangePicker(
                onRangeChanged: _loadHistory,
                isLoading: isLoading,
              ),
            ),

            // Empty state
            if (!isLoading && entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5)),
                    const SizedBox(width: 6),
                    Text(
                      'Không có dữ liệu trong khoảng thời gian này',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _calcSize(ClusteredHistoryEntry cluster) {
    final minutes = cluster.duration.inMinutes;
    if (minutes <= 0) return 14.0;
    // Scale marker icon size from 14.0 to 38.0 based on stay duration
    final extra = min(minutes / 15.0, 24.0);
    return 14.0 + extra;
  }

  Marker _buildPopupMarker(ClusteredHistoryEntry cluster) {
    final isSameTime = cluster.startTime.isAtSameMomentAs(cluster.endTime);

    return Marker(
      point: LatLng(cluster.latitude, cluster.longitude),
      width: 250,
      height: isSameTime ? 110 : 135,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '📍 ${cluster.latitude.toStringAsFixed(5)}, ${cluster.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (isSameTime)
                Text(
                  '🕐 ${_fmtDateTime(cluster.startTime.toLocal())}',
                  style: const TextStyle(fontSize: 11),
                )
              else ...[
                Text(
                  '🕐 ${_fmtDateTime(cluster.startTime.toLocal())}',
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  ' ➔ ${_fmtDateTime(cluster.endTime.toLocal())}',
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  '⏳ Thời gian ở đây: ${_fmtDuration(cluster.duration)}',
                  style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.w500),
                ),
              ],
              if (cluster.batteryStatus != null)
                Text(
                  '🔋 ${cluster.batteryStatus}',
                  style: const TextStyle(fontSize: 11),
                ),
              Text(
                '📊 Báo cáo gộp: ${cluster.rawEntries.length}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    if (d.inHours > 0) {
      final mins = d.inMinutes % 60;
      return mins > 0 ? '${d.inHours} giờ $mins phút' : '${d.inHours} giờ';
    }
    return '${d.inMinutes} phút';
  }

  String _fmtDateTime(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
