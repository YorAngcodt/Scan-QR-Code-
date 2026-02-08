import 'package:flutter/material.dart';
import '../configuration/main_assets_list_page.dart';
import '../configuration/asset_category_list_page.dart';
import '../configuration/location_assets_list_page.dart';
import '../configuration/maintenance_teams_list_page.dart';

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
            ),
            const SizedBox(height: 16),
            _ConfigTile(
              icon: Icons.apps_outage_outlined,
              title: 'Main Assets',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MainAssetsListPage()),
              ),
            ),
            _ConfigTile(
              icon: Icons.category_outlined,
              title: 'Asset Category',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AssetCategoryListPage()),
              ),
            ),
            _ConfigTile(
              icon: Icons.place_outlined,
              title: 'Location Assets',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LocationAssetsListPage()),
              ),
            ),
            _ConfigTile(
              icon: Icons.groups_outlined,
              title: 'Maintenance Teams',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MaintenanceTeamsListPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _ConfigTile({required this.icon, required this.title, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1E3A8A)),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
