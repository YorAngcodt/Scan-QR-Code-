import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'pages/auth/url_input_screen.dart';
import 'pages/auth/database_selection_screen.dart';
import 'pages/auth/login_screen.dart';
import 'pages/home_page.dart';
import 'pages/history_page.dart';
import 'pages/scan_page.dart';
import 'pages/profile_page.dart';
import 'pages/categories/asset_page.dart';
import 'pages/categories/maintenance_page.dart';
import 'pages/categories/employees_page.dart';
import 'pages/categories/transfer_page.dart';
import 'pages/categories/calendar_page.dart';
import 'pages/configuration/configuration_page.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  ApiService.baseUrl = null;  // Will be set during URL input
  ApiService.selectedDatabase = null;
  
  // Check if user is logged in
  final isLoggedIn = await AuthService.isLoggedIn();
  
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Add any providers here if needed
        Provider(create: (_) => Object()),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          title: 'Asset Maintenance',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
            useMaterial3: true,
            snackBarTheme: const SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 80),
            ),
          ),
          initialRoute: isLoggedIn ? '/home' : '/login',
          routes: {
            '/': (context) => const UrlInputScreen(),
            '/databases': (context) => const DatabaseSelectionScreen(),
            '/login': (context) => const LoginScreen(),
            '/home': (context) => const MainScreen(),
          },
          onGenerateRoute: (settings) {
            // Handle unauthorized access and redirect to home if already logged in
            if (isLoggedIn && settings.name == '/login') {
              return MaterialPageRoute(builder: (context) => const MainScreen());
            }
            return null;
          },
          navigatorKey: navigatorKey,
        ),
      ),
    );
  }
  
  // Global key for navigation to handle navigation from anywhere
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Static method to handle logout from anywhere in the app
  static Future<void> logout() async {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      await AuthService.logout();
      // Navigate to login screen and remove all previous routes from the stack
      navigator.pushNamedAndRemoveUntil(
        '/login',  // Go to login screen after logout
        (route) => false, // Remove all previous routes
      );
    }
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static MainScreenState? of(BuildContext context) {
    return context.findRootAncestorStateOfType<MainScreenState>();
  }

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  
  // Handle back button press
  Future<bool> _onWillPop() async {
    if (_currentCategory != null) {
      // If a category is open, close it instead of exiting the app
      closeCategoryPage();
      return false; // Prevent default back behavior
    }
    
    // If on home screen, show exit confirmation
    if (_selectedIndex == 0) {
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Exit App'),
          content: const Text('Are you sure you want to exit?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      return shouldExit ?? false;
    } else {
      // For other tabs, go back to home first
      setState(() => _selectedIndex = 0);
      return false; // Prevent default back behavior
    }
  }
  static const Color navyBlue = Color(0xFF1E3A8A);
  static const Color activeIconColor = Colors.white;
  static const Color inactiveIconColor = Color(0xFF9CA3AF);

  // Track the current category
  String? _currentCategory;
  
  // Main pages for bottom navigation
  late final List<Widget> _pages;
  
  // Category pages
  late final Map<String, Widget> _categoryPages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomePage(),
      const HistoryPage(),
      const ScanPage(),
      const ProfilePage(),
    ];
    
    _categoryPages = {
      'asset': const AssetPage(),
      'maintenance': const MaintenancePage(),
      'employees': const EmployeesPage(),
      'transfer': const TransferPage(),
      'calendar': const CalendarPage(),
      'configuration': const ConfigurationPage(),
    };
  }
  
  // Show category page
  void showCategoryPage(String category) {
    if (_categoryPages.containsKey(category)) {
      setState(() {
        _currentCategory = category;
      });
    }
  }
  
  // Close category page
  void closeCategoryPage() {
    setState(() {
      _currentCategory = null;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      // Close any open category when switching tabs
      _currentCategory = null;
    });
  }

  // Public method to switch tabs from child pages (e.g., ScanPage)
  void goToTab(int index) {
    _onItemTapped(index);
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final bool isActive = _selectedIndex == index;
    final Color color = isActive ? activeIconColor : inactiveIconColor;

    return InkWell(
      onTap: () => _onItemTapped(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          children: [
            Icon(isActive ? activeIcon : icon, color: color),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          if (_currentCategory != null) {
            closeCategoryPage();
          } else if (_selectedIndex != 0) {
            setState(() => _selectedIndex = 0);
          } else {
            SystemNavigator.pop(animated: true);
          }
        }
      },
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build, size: 28),
            const SizedBox(width: 12),
            Text(
              'Asset Maintenance',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.grey[800]),
        automaticallyImplyLeading: _currentCategory != null,
        leading: _currentCategory != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: closeCategoryPage,
              )
            : null,
      ),
      body: _currentCategory != null
          ? Stack(
              children: [
                _pages[_selectedIndex],
                Positioned.fill(
                  child: _categoryPages[_currentCategory]!,
                ),
              ],
            )
          : _pages[_selectedIndex],
      floatingActionButton: Transform.translate(
        offset: const Offset(0, 6),
        child: SizedBox(
          width: 64,
          height: 64,
          child: FloatingActionButton(
            onPressed: () => _onItemTapped(2),
            backgroundColor: Colors.cyan,
            shape: const CircleBorder(
              side: BorderSide(color: Colors.white, width: 4),
            ),
            child: const Icon(
              Icons.qr_code_scanner,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: navyBlue,
        shape: const CircularNotchedRectangle(),
        notchMargin: 10,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
              ),
              const SizedBox(width: 48),
              _buildNavItem(
                index: 3,
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
