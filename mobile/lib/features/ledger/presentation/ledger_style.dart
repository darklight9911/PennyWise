import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';

/// Icons the server's default categories use, plus a few extra choices.
/// Stored by name so the server and every phone agree.
const categoryIcons = <String, AppIconData>{
  'restaurant': HugeIcons.strokeRoundedRestaurant01,
  'local_grocery_store': HugeIcons.strokeRoundedShoppingCart01,
  'directions_bus': HugeIcons.strokeRoundedBus01,
  'home': HugeIcons.strokeRoundedHome01,
  'receipt_long': HugeIcons.strokeRoundedInvoice01,
  'shopping_bag': HugeIcons.strokeRoundedShoppingBag01,
  'medical_services': HugeIcons.strokeRoundedMedicine01,
  'movie': HugeIcons.strokeRoundedFilm01,
  'school': HugeIcons.strokeRoundedSchool01,
  'flight': HugeIcons.strokeRoundedAirplane01,
  'spa': HugeIcons.strokeRoundedLeaf01,
  'card_giftcard': HugeIcons.strokeRoundedGiftCard,
  'more_horiz': HugeIcons.strokeRoundedMoreHorizontal,
  'payments': HugeIcons.strokeRoundedMoney03,
  'storefront': HugeIcons.strokeRoundedStore01,
  'work': HugeIcons.strokeRoundedBriefcase01,
  'redeem': HugeIcons.strokeRoundedGift,
  'savings': HugeIcons.strokeRoundedPiggyBank,
  'attach_money': HugeIcons.strokeRoundedDollarCircle,
  'local_cafe': HugeIcons.strokeRoundedCoffee01,
  'pets': HugeIcons.strokeRoundedCat,
  'fitness_center': HugeIcons.strokeRoundedDumbbell01,
  'phone_iphone': HugeIcons.strokeRoundedSmartPhone01,
  'child_care': HugeIcons.strokeRoundedBabyBottle,
};

AppIconData categoryIcon(String name) =>
    categoryIcons[name] ?? HugeIcons.strokeRoundedTag01;

/// Account types the server accepts, with a label and icon each.
const accountTypes = <String, (String, AppIconData)>{
  'cash': ('Cash', HugeIcons.strokeRoundedMoney03),
  'bank': ('Bank account', HugeIcons.strokeRoundedBank),
  'card': ('Card', HugeIcons.strokeRoundedCreditCard),
  'ewallet': ('E-wallet', HugeIcons.strokeRoundedSmartPhone01),
  'savings': ('Savings', HugeIcons.strokeRoundedPiggyBank),
  'other': ('Other', HugeIcons.strokeRoundedWallet01),
};

AppIconData accountIcon(String type) =>
    accountTypes[type]?.$2 ?? HugeIcons.strokeRoundedWallet01;

/// Colour choices for categories (muted, readable with white icons).
const swatches = [
  '#E07A5F', '#81B29A', '#3D5A80', '#9C6644', '#5C6B69', '#C77DFF', //
  '#D62828', '#F2A541', '#4361EE', '#2A9D8F', '#E5989B', '#B5838D',
  '#8D99AE', '#2F7734', '#2C706E', '#729D99',
];

/// Parses "#RRGGBB"; falls back to [fallback] when empty or invalid.
Color colorFromHex(String hex, Color fallback) {
  final m = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(hex);
  return m == null
      ? fallback
      : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

/// Round coloured badge with an icon, used in lists.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final AppIconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: AppIcon(icon, color: Colors.white, size: size * 0.55),
    );
  }
}
