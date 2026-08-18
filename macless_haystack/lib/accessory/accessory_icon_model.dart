import 'package:flutter/material.dart';

class AccessoryIconModel {
  /// A list of all available icons
  static const List<String> icons = [
    // Phương tiện di chuyển (Vehicles)
    "car.fill", "motorcycle", "electric_scooter", "bicycle", "bus.fill", "truck.fill", "airplane", "boat.fill",

    // Đồ dùng cá nhân & Hành lý (Belongings & Luggage)
    "key.fill", "wallet", "creditcard.fill", "briefcase.fill", "case.fill", "backpack", "luggage", "shopping_bag", "watch",

    // Thiết bị công nghệ (Electronics)
    "laptop", "phone", "tablet", "headphones", "camera",

    // Người thân & Thú cưng (People & Pets)
    "figure.walk", "person", "child", "face", "hare.fill", "cat",

    // Địa điểm & Biểu tượng (Places & Symbols)
    "mappin", "house", "building", "store", "globe", "heart.fill", "crown.fill", "star", "gift.fill", "shield", "tool",
  ];

  /// A mapping from the icon names to the material icon names.
  static const iconMapping = {
    // Phương tiện
    'car.fill': Icons.directions_car,
    'motorcycle': Icons.two_wheeler,
    'motorcycle.fill': Icons.two_wheeler,
    'electric_scooter': Icons.electric_scooter,
    'bicycle': Icons.pedal_bike,
    'bus.fill': Icons.directions_bus,
    'truck.fill': Icons.local_shipping,
    'airplane': Icons.flight,
    'boat.fill': Icons.directions_boat,

    // Đồ dùng cá nhân
    'key.fill': Icons.vpn_key,
    'wallet': Icons.account_balance_wallet,
    'creditcard.fill': Icons.credit_card,
    'briefcase.fill': Icons.business_center,
    'case.fill': Icons.work,
    'latch.2.case.fill': Icons.business_center,
    'backpack': Icons.backpack,
    'luggage': Icons.luggage,
    'shopping_bag': Icons.shopping_bag,
    'watch': Icons.watch,

    // Công nghệ
    'laptop': Icons.laptop_mac,
    'phone': Icons.phone_iphone,
    'tablet': Icons.tablet_mac,
    'headphones': Icons.headphones,
    'camera': Icons.photo_camera,

    // Người thân & Thú cưng
    'figure.walk': Icons.directions_walk,
    'person': Icons.person,
    'child': Icons.child_care,
    'face': Icons.face,
    'hare.fill': Icons.pets,
    'cat': Icons.cruelty_free,
    'tortoise.fill': Icons.pets,
    'eye.fill': Icons.two_wheeler,

    // Địa điểm & Biểu tượng
    'mappin': Icons.place,
    'house': Icons.home,
    'building': Icons.apartment,
    'store': Icons.storefront,
    'globe': Icons.language,
    'heart.fill': Icons.favorite,
    'crown.fill': Icons.school,
    'star': Icons.star,
    'gift.fill': Icons.redeem,
    'shield': Icons.shield,
    'tool': Icons.build,
  };

  /// Looks up the equivalent material icon for the cupertino icon [iconName].
  static IconData? mapIcon(String iconName) {
    return iconMapping[iconName];
  }
}
