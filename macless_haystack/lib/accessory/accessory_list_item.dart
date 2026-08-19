
import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:macless_haystack/accessory/accessory_icon.dart';
import 'package:macless_haystack/accessory/accessory_model.dart';
import 'package:intl/intl.dart';

import 'accessory_battery.dart';

class AccessoryListItem extends StatefulWidget {
  final Accessory accessory;
  final String? distanceText;
  final Placemark? herePlace;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const AccessoryListItem({
    super.key,
    required this.accessory,
    required this.onTap,
    this.onLongPress,
    this.distanceText,
    this.herePlace,
  });

  @override
  AccessoryListItemState createState() => AccessoryListItemState();
}

class AccessoryListItemState extends State<AccessoryListItem> {
  Color _tileColor = Colors.transparent;

  @override
  Widget build(BuildContext context) {
    var hasChanged = widget.accessory.hasChangedFlag;
    if (hasChanged) {
      _tileColor = widget.accessory.color.withAlpha(50);
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          widget.accessory.hasChangedFlag = false;
          setState(() {
            _tileColor = Colors.transparent;
          });
        }
      });
    }
    // Format published date: Ngày trước, giờ sau (dd/MM/yyyy - HH:mm)
    final String dateString = widget.accessory.datePublished != null &&
            widget.accessory.datePublished != DateTime(1970)
        ? DateFormat('dd/MM/yyyy - HH:mm').format(widget.accessory.datePublished!)
        : 'Chưa có vị trí';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: _tileColor,
      child: ListTile(
        onTap: widget.onTap,
        dense: true,
        leading: GestureDetector(
          onLongPress: widget.onLongPress,
          child: AccessoryIcon(
            icon: widget.accessory.icon,
            color: widget.accessory.color,
          ),
        ),
        title: Text(
          widget.accessory.name +
              (widget.accessory.isActive ? '' : ' (inactive)'),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: widget.accessory.isActive
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).disabledColor,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          dateString,
          style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade400
                : Colors.grey.shade600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Fixed-width distance column (cố định độ rộng để pin luôn thẳng hàng)
            SizedBox(
              width: 58,
              child: Text(
                widget.distanceText ?? '',
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade400
                      : Colors.grey.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Fixed-width Battery icon column (luôn thẳng hàng theo trục dọc)
            SizedBox(
              width: 18,
              child: Center(
                child: _buildBatteryIcon(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryIcon() {
    switch (widget.accessory.lastBatteryStatus) {
      case AccessoryBatteryStatus.ok:
        return const Icon(Icons.battery_full, color: Colors.green, size: 16);
      case AccessoryBatteryStatus.medium:
        return const Icon(Icons.battery_3_bar, color: Colors.orange, size: 16);
      case AccessoryBatteryStatus.low:
        return const Icon(Icons.battery_1_bar, color: Colors.red, size: 16);
      case AccessoryBatteryStatus.criticalLow:
        return const Icon(Icons.battery_alert, color: Colors.red, size: 16);
      default:
        return const SizedBox(width: 16);
    }
  }
}
