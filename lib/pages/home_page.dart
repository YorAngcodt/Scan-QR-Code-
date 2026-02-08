import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'configuration/main_assets_list_page.dart';
import 'configuration/asset_category_list_page.dart';
import 'configuration/location_assets_list_page.dart';
import 'configuration/maintenance_teams_list_page.dart';
import 'categories/reporting_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isManager = false;
  bool _isTeam = false;
  int _tabIndex = 0;

  bool get _canAccessReporting => _isManager || _isTeam;

  @override
  Widget build(BuildContext context) {
    final tabs = <Map<String, dynamic>>[
      {
        'icon': Icons.inventory_2_outlined,
        'label': 'Asset',
        'items': _assetCategories,
      },
      {
        'icon': Icons.build_outlined,
        'label': 'Maintenance',
        'items': _maintenanceCategories,
      },
      if (_canAccessReporting)
        {
          'icon': Icons.bar_chart_outlined,
          'label': 'Reporting',
          'items': null,
        },
      if (_isManager)
        {
          'icon': Icons.settings_outlined,
          'label': 'Configuration',
          'items': _configurationCategories,
        },
    ];

    final bool isManagerLayout = _isManager && tabs.length >= 4;

    // Reporting tab index no longer used for auto-popup; dialogs are opened from buttons inside the tab

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = DefaultTabController.of(context);
      if (controller.index != _tabIndex &&
          controller.length == tabs.length) {
        controller.index = _tabIndex;
      }
    });

    return RefreshIndicator(
      onRefresh: _loadRole,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: DefaultTabController(
          length: tabs.length,
          initialIndex: _tabIndex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                // Semua role: tab mengisi lebar layar (kiri, tengah, kanan, dst).
                isScrollable: false,
                // Untuk manager, sedikit padding di kiri/kanan label agar tidak terlalu dempet.
                labelPadding: isManagerLayout
                    ? const EdgeInsets.symmetric(horizontal: 4.0)
                    : EdgeInsets.zero,
                indicatorPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                labelColor: const Color(0xFF1E3A8A),
                unselectedLabelColor: const Color(0xFF1E3A8A),
                labelStyle: TextStyle(
                  fontSize: isManagerLayout ? 11 : 12,
                  fontWeight: FontWeight.w500,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: isManagerLayout ? 11 : 12,
                  fontWeight: FontWeight.w500,
                ),
                indicatorColor: const Color(0xFF1E3A8A),
                onTap: (index) {
                  setState(() {
                    _tabIndex = index;
                  });
                },
                tabs: tabs
                    .map((t) => Tab(
                          icon: Icon(t['icon'] as IconData),
                          text: t['label'] as String,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: tabs.map((t) {
                    if (t['label'] == 'Reporting') {
                      return _buildReportingTab();
                    }
                    return _buildCategoryGrid(
                        t['items'] as List<Map<String, dynamic>>);
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    // 1) Use cached role immediately
    try {
      final cached = await AuthService.getUserRole();
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() {
          _isManager = cached == 'Manager';
          _isTeam = cached == 'Team';
        });
      }
    } catch (_) {}

    // 2) Refresh from API and persist
    try {
      final info = await ApiService.fetchCurrentUserInfo();
      final role = (info['role'] ?? '').toString();
      if (!mounted) return;
      setState(() {
        _isManager = role == 'Manager';
        _isTeam = role == 'Team';
      });
    } catch (_) {
      // keep cached state
    }
  }

  final List<Map<String, dynamic>> _assetCategories = [
    {
      'icon': Icons.inventory_2_outlined,
      'label': 'Asset',
      'onTap': (BuildContext context) {
        MainScreen.of(context)?.showCategoryPage('asset');
      },
    },
    {
      'icon': Icons.people_outline,
      'label': 'Employees',
      'onTap': (BuildContext context) {
        MainScreen.of(context)?.showCategoryPage('employees');
      },
    },
    {
      'icon': Icons.swap_horiz_outlined,
      'label': 'Asset Transfer',
      'onTap': (BuildContext context) {
        MainScreen.of(context)?.showCategoryPage('transfer');
      },
    },
  ];

  final List<Map<String, dynamic>> _configurationCategories = [
    {
      'icon': Icons.apps_outage_outlined,
      'label': 'Main Assets',
      'onTap': (BuildContext context) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MainAssetsListPage()));
      },
    },
    {
      'icon': Icons.category_outlined,
      'label': 'Asset Category',
      'onTap': (BuildContext context) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AssetCategoryListPage()));
      },
    },
    {
      'icon': Icons.place_outlined,
      'label': 'Location Assets',
      'onTap': (BuildContext context) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const LocationAssetsListPage()));
      },
    },
    {
      'icon': Icons.groups_outlined,
      'label': 'Maintenance Teams',
      'onTap': (BuildContext context) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MaintenanceTeamsListPage()));
      },
    },
  ];

  final List<Map<String, dynamic>> _maintenanceCategories = [
    {
      'icon': Icons.build_outlined,
      'label': 'Maintenance',
      'onTap': (BuildContext context) {
        MainScreen.of(context)?.showCategoryPage('maintenance');
      },
    },
    {
      'icon': Icons.calendar_today_outlined,
      'label': 'Calendar',
      'onTap': (BuildContext context) {
        MainScreen.of(context)?.showCategoryPage('calendar');
      },
    },
  ];

  Widget _buildReportingTab() {
    final List<Map<String, dynamic>> reportingMenus = [
      {
        'icon': Icons.inventory_2_outlined,
        'label': 'Report Asset',
        'onTap': (BuildContext context) {
          _showReportingDialog(initialType: 'asset');
        },
      },
      {
        'icon': Icons.qr_code_2_outlined,
        'label': 'Report Asset QR',
        'onTap': (BuildContext context) {
          _showReportingDialog(initialType: 'asset_qr');
        },
      },
      {
        'icon': Icons.swap_horiz,
        'label': 'Report Asset Transfers',
        'onTap': (BuildContext context) {
          _showReportingDialog(initialType: 'asset_transfer');
        },
      },
      {
        'icon': Icons.build_outlined,
        'label': 'Report Maintenance',
        'onTap': (BuildContext context) {
          _showReportingDialog(initialType: 'maintenance');
        },
      },
    ];
    return _buildCategoryGrid(reportingMenus);
  }

  Widget _buildCategoryGrid(List<Map<String, dynamic>> categories) {
    return GridView.count(
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.8,
      children: categories.map((category) {
        return _buildCategoryButton(
          context,
          icon: category['icon'],
          label: category['label'],
          onTap: () => category['onTap'](context),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Color.lerp(Colors.grey, Colors.white, 0.8)!.withAlpha(51),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: const Color(0xFF1E3A8A),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1E3A8A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportingDialog({String? initialType}) {
    showDialog(
      context: context,
      builder: (context) => ReportingDialog(initialReportType: initialType),
    );
  }

  // Removed custom button tabs; using TabBar instead
}
