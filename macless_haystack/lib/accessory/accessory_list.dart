import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:macless_haystack/dashboard/app_toast.dart';
import 'package:macless_haystack/accessory/accessory_list_item.dart';
import 'package:macless_haystack/accessory/accessory_list_item_placeholder.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/accessory/no_accessories.dart';
import 'package:macless_haystack/history/accessory_history.dart';
import 'package:macless_haystack/location/location_model.dart';

import '../callbacks.dart';
import '../radar/tag_radar_dialog.dart';
import 'accessory_model.dart';

class AccessoryList extends StatefulWidget {
  final LoadLocationUpdatesCallback loadLocationUpdates;
  final SaveOrderUpdatesCallback saveOrderUpdatesCallback;
  final void Function(LatLng point)? centerOnPoint;

  /// Display a location overview all accessories in a concise list form.
  ///
  /// For each accessory the name and last known locaiton information is shown.
  /// Uses the accessories in the [AccessoryRegistry].
  const AccessoryList({
    super.key,
    required this.loadLocationUpdates,
    this.centerOnPoint,
    required this.saveOrderUpdatesCallback,
  });

  @override
  State<StatefulWidget> createState() {
    return _AccessoryListState();
  }
}

class _AccessoryListState extends State<AccessoryList> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<AccessoryRegistry, LocationModel>(
      builder: (context, accessoryRegistry, locationModel, child) {
        var accessories =
            accessoryRegistry.accessories.where((a) => a.isActive).toList();

        // Show placeholder while accessories are loading
        if (accessoryRegistry.loading) {
          return LayoutBuilder(builder: (context, constraints) {
            // Show as many accessory placeholder fitting into the vertical space.
            // Minimum one, maximum 6 placeholders
            var nrOfEntries =
                min(max((constraints.maxHeight / 64).floor(), 1), 6);
            List<Widget> placeholderList = [];
            for (int i = 0; i < nrOfEntries; i++) {
              placeholderList.add(const AccessoryListItemPlaceholder());
            }
            return Scrollbar(
              child: ListView(
                children: placeholderList,
              ),
            );
          });
        }

        if (accessories.isEmpty) {
          return const NoAccessoriesPlaceholder();
        }
        // Use pull to refresh method
        return SlidableAutoCloseBehavior(
          child: Scrollbar(
            child: ListView.builder(
              itemCount: accessories.length,
              itemBuilder: (context, index) {
                var accessory = accessories[index];
                // Calculate distance from users devices location
                String? distanceStr;
                if (locationModel.here != null &&
                    accessory.lastLocation != null) {
                  const Distance distance = Distance();
                  final double km = distance.as(LengthUnit.Kilometer,
                      locationModel.here!, accessory.lastLocation!);
                  if (km < 1) {
                    distanceStr = '${(km * 1000).round()} m';
                  } else if (km < 10) {
                    distanceStr = '${km.toStringAsFixed(1)} km';
                  } else {
                    distanceStr = '${km.round()} km';
                  }
                }
                final bool isTrackingThis =
                    accessoryRegistry.trackedAccessoryKey == accessory.hashedPublicKey;

                return Slidable(
                  key: ValueKey(accessory),
                  startActionPane: !accessory.isActive
                      ? null
                      : ActionPane(
                          key: ValueKey('track_${accessory.hashedPublicKey}'),
                          motion: const ScrollMotion(),
                          dragDismissible: false,
                          children: [
                            SlidableAction(
                              onPressed: (context) {
                                showDialog(
                                  context: context,
                                  builder: (ctx) =>
                                      TagRadarDialog(accessory: accessory),
                                );
                              },
                              backgroundColor: Colors.deepPurple.shade700,
                              foregroundColor: Colors.white,
                              icon: Icons.sensors,
                              label: 'Dò sóng',
                            ),
                            SlidableAction(
                              onPressed: (context) {
                                if (isTrackingThis) {
                                  accessoryRegistry.clearTrackedAccessory();
                                  AppToast.showText(
                                    context,
                                    'Đã dừng theo dõi "${accessory.name}"',
                                    icon: Icons.check_circle,
                                    backgroundColor: Colors.grey.shade800,
                                  );
                                } else {
                                  if (accessory.lastLocation == null) {
                                    AppToast.showText(
                                      context,
                                      'Tag "${accessory.name}" chưa có vị trí để theo dõi!',
                                      icon: Icons.warning_amber_rounded,
                                      backgroundColor: Colors.amber.shade900,
                                    );
                                    return;
                                  }
                                  if (locationModel.here == null) {
                                    locationModel.requestLocationUpdates();
                                  }
                                  accessoryRegistry.setTrackedAccessory(accessory);
                                  AppToast.showText(
                                    context,
                                    'Bật chế độ theo dõi "${accessory.name}" cùng vị trí thiết bị',
                                    icon: Icons.radar,
                                    backgroundColor: Colors.teal.shade800,
                                  );
                                }
                              },
                              backgroundColor: isTrackingThis ? Colors.red.shade700 : Colors.teal.shade700,
                              foregroundColor: Colors.white,
                              icon: isTrackingThis ? Icons.close : Icons.radar,
                              label: isTrackingThis ? 'Dừng theo dõi' : 'Theo dõi',
                            ),
                          ],
                        ),
                  endActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    children: [
                      if (accessory.isActive)
                        SlidableAction(
                          onPressed: (context) async {
                            if (accessory.lastLocation != null &&
                                accessory.isActive) {
                              var loc = accessory.lastLocation!;
                              final uri = Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}');
                              try {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              } catch (_) {}
                            }
                          },
                          foregroundColor: Theme.of(context).primaryColor,
                          icon: Icons.directions,
                          label: 'Navigate',
                        ),
                      if (accessory.isActive)
                        SlidableAction(
                          onPressed: (context) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => AccessoryHistory(
                                        accessory: accessory,
                                      )),
                            );
                          },
                          backgroundColor: Theme.of(context).primaryColor,
                          icon: Icons.history,
                          label: 'History',
                        ),
                      if (!accessory.isActive)
                        SlidableAction(
                          onPressed: (context) {
                            var accessoryRegistry =
                                Provider.of<AccessoryRegistry>(context,
                                    listen: false);
                            var newAccessory = accessory.clone();
                            newAccessory.isActive = true;
                            accessoryRegistry.editAccessory(
                                accessory, newAccessory);
                          },
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          icon: Icons.toggle_on_outlined,
                          label: 'Activate',
                        ),
                    ],
                  ),
                  child: Builder(builder: (context) {
                    return AccessoryListItem(
                      accessory: accessory,
                      distanceText: distanceStr,
                      herePlace: locationModel.herePlace,
                      isTracked: isTrackingThis,
                      onTap: () {
                        if (accessory.isActive) {
                          var lastLocation = accessory.lastLocation;
                          if (lastLocation != null) {
                            widget.centerOnPoint?.call(lastLocation);
                          }
                        }
                      },
                      onLongPress: !accessory.isActive
                          ? null
                          : () async {
                              await widget.loadLocationUpdates(accessory);
                            },
                    );
                  }),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
