import 'package:material_ui/material_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.payments_outlined),
            title: Text('Base currency'),
            subtitle: Text('USD'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About pennyWise'),
            subtitle: Text('Version 0.1.0'),
          ),
        ],
      ),
    );
  }
}
