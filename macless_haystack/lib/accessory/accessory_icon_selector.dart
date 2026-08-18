import 'dart:math';

import 'package:flutter/material.dart';
import 'package:macless_haystack/accessory/accessory_icon_model.dart';

typedef IconChangeListener = void Function(String? newValue);

class AccessoryIconSelector extends StatelessWidget {
  /// The existing icon used previously.
  final String icon;
  /// The existing color used previously.
  final Color color;
  /// A callback being called when the icon changes.
  final IconChangeListener iconChanged;

  /// This show an icon selector.
  /// 
  /// The icon can be selected from a list of available icons.
  /// The icons are handled by the cupertino icon names.
  const AccessoryIconSelector({
    super.key,
    required this.icon,
    required this.color,
    required this.iconChanged,
  });

  /// Displays the icon selector with the [currentIcon] preselected in the [highlighColor].
  /// 
  /// The selected icon as a cupertino icon name is returned if the user selects an icon.
  /// Otherwise the selection is discarded and a null value is returned.
  static Future<String?> showIconSelection(BuildContext context, String currentIcon, Color highlighColor) async {
    return await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return LayoutBuilder(
          builder: (context, constraints) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 520),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: highlighColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.category_outlined, color: highlighColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text('Chọn biểu tượng Thẻ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.count(
                      primary: false,
                      padding: const EdgeInsets.all(4),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      shrinkWrap: true,
                      crossAxisCount: min((constraints.maxWidth / 70).floor().clamp(4, 7), 6),
                      semanticChildCount: AccessoryIconModel.icons.length,
                      children: AccessoryIconModel.icons.map((value) {
                        final isSel = value == currentIcon;
                        final iconData = AccessoryIconModel.mapIcon(value) ?? Icons.place;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(context, value),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSel ? highlighColor.withOpacity(0.18) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? highlighColor : Colors.grey.withOpacity(0.25),
                                width: isSel ? 2.2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                iconData,
                                color: isSel ? highlighColor : null,
                                size: 24,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color.fromARGB(255, 200, 200, 200),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: () async {
          String? selectedIcon = await showIconSelection(context, icon, color);
          if (selectedIcon != null) {
            iconChanged(selectedIcon);
          }
        },
        icon: Icon(AccessoryIconModel.mapIcon(icon)),
      ),
    );
  }
}
