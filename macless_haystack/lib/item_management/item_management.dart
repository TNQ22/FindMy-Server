import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:macless_haystack/accessory/accessory_detail.dart';
import 'package:macless_haystack/accessory/accessory_icon.dart';
import 'package:macless_haystack/accessory/no_accessories.dart';
import 'package:macless_haystack/item_management/item_export.dart';
import 'package:macless_haystack/item_management/item_share.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:intl/intl.dart';

class KeyManagement extends StatelessWidget {
  /// Displays a list of all accessories.
  ///
  /// Each accessory can be exported and is linked to a detail page.
  const KeyManagement({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AccessoryRegistry>(
      builder: (context, accessoryRegistry, child) {
        var accessories = accessoryRegistry.accessories;

        if (accessories.isEmpty) {
          return const NoAccessoriesPlaceholder();
        }

        return Scrollbar(
          child: ListView(
            children: accessories.map((accessory) {
              String lastSeen = accessory.datePublished != null &&
                      accessory.datePublished != DateTime(1970)
                  ? DateFormat('dd/MM/yyyy - HH:mm')
                      .format(accessory.datePublished!)
                  : 'Chưa có vị trí';
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AccessoryDetail(
                        accessory: accessory,
                      ),
                    );
                  },
                  title: Text(
                    accessory.name + (accessory.isActive ? '' : ' (inactive)'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: accessory.isActive
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).disabledColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    lastSeen,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: Opacity(
                    opacity: accessory.isActive ? 1.0 : 0.5,
                    child: AccessoryIcon(
                      icon: accessory.icon,
                      color: accessory.color,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ItemShareAction(accessory: accessory),
                      ItemExportMenu(accessory: accessory),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

