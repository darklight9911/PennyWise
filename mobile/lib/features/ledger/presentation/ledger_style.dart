import 'package:material_ui/material_ui.dart';

/// Icons the server's default categories use, plus a few extra choices.
/// Stored by name so the server and every phone agree.
const categoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'local_grocery_store': Icons.local_grocery_store,
  'directions_bus': Icons.directions_bus,
  'home': Icons.home_outlined,
  'receipt_long': Icons.receipt_long,
  'shopping_bag': Icons.shopping_bag_outlined,
  'medical_services': Icons.medical_services_outlined,
  'movie': Icons.movie_outlined,
  'school': Icons.school_outlined,
  'flight': Icons.flight,
  'spa': Icons.spa_outlined,
  'card_giftcard': Icons.card_giftcard,
  'more_horiz': Icons.more_horiz,
  'payments': Icons.payments_outlined,
  'storefront': Icons.storefront_outlined,
  'work': Icons.work_outline,
  'redeem': Icons.redeem,
  'savings': Icons.savings_outlined,
  'attach_money': Icons.attach_money,
  'local_cafe': Icons.local_cafe_outlined,
  'pets': Icons.pets,
  'fitness_center': Icons.fitness_center,
  'phone_iphone': Icons.phone_iphone,
  'child_care': Icons.child_care,
};

IconData categoryIcon(String name) =>
    categoryIcons[name] ?? Icons.label_outline;

/// Account types the server accepts, with a label and icon each.
const accountTypes = <String, (String, IconData)>{
  'cash': ('Cash', Icons.payments_outlined),
  'bank': ('Bank account', Icons.account_balance_outlined),
  'card': ('Card', Icons.credit_card),
  'ewallet': ('E-wallet', Icons.phone_iphone),
  'savings': ('Savings', Icons.savings_outlined),
  'other': ('Other', Icons.account_balance_wallet_outlined),
};

IconData accountIcon(String type) =>
    accountTypes[type]?.$2 ?? Icons.account_balance_wallet_outlined;

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

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: size * 0.55),
    );
  }
}
