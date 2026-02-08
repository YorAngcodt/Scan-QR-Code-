import 'package:flutter/material.dart';
import '../../models/database_info.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class DatabaseSelectionScreen extends StatefulWidget {
  const DatabaseSelectionScreen({super.key});

  @override
  State<DatabaseSelectionScreen> createState() => _DatabaseSelectionScreenState();
}

class _DatabaseSelectionScreenState extends State<DatabaseSelectionScreen> 
    with SingleTickerProviderStateMixin {
  List<DatabaseInfo> _databases = [];
  bool _isLoading = true;
  String? _error;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    
    _animationController.forward();
    _initAndFetch();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initAndFetch() async {
    // Ensure baseUrl is available when navigating here directly
    if (ApiService.baseUrl == null || (ApiService.baseUrl?.isEmpty ?? true)) {
      final cfg = await AuthService.getServerConfig();
      final savedUrl = cfg['serverUrl'] ?? '';
      if (savedUrl.isNotEmpty) {
        ApiService.baseUrl = savedUrl;
      }
    }
    if (mounted) {
      _fetchDatabases();
    }
  }

  Future<void> _fetchDatabases() async {
    try {
      final databases = await ApiService.fetchDatabases(ApiService.baseUrl!);
      setState(() {
        _databases = databases;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat database. Silakan periksa URL dan coba lagi.';
        _isLoading = false;
      });
    }
  }

  Future<void> _onDatabaseSelected(DatabaseInfo database) async {
    ApiService.selectedDatabase = database.name;
    final serverUrl = ApiService.baseUrl ?? '';
    if (serverUrl.isNotEmpty) {
      await AuthService.saveServerConfig(serverUrl: serverUrl, database: database.name);
    }
    if (mounted) {
      Navigator.pushNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1E3A8A), // Deep blue
              const Color(0xFF1E40AF),
              const Color(0xFF3B82F6), // Lighter blue
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        
                        // Logo/Icon Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.storage_rounded,
                              size: 60,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Title Section
                        const Text(
                          'Pilih Database',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Pilih database yang akan digunakan untuk sistem',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                              letterSpacing: 0.3,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Database List
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: _isLoading
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const CircularProgressIndicator(
                                          color: Color(0xFF1E3A8A),
                                          strokeWidth: 3,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Memuat database...',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : _error != null
                                    ? Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24.0),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFEE2E2),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.error_outline,
                                                  color: Color(0xFFDC2626),
                                                  size: 48,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                _error!,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.grey[700],
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : _databases.isEmpty
                                        ? Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(16),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[100],
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    Icons.inbox_outlined,
                                                    color: Colors.grey[400],
                                                    size: 48,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  'Tidak ada database yang ditemukan',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Database Tersedia',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey[800],
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${_databases.length} database ditemukan',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              Expanded(
                                                child: ListView.builder(
                                                  physics: const BouncingScrollPhysics(),
                                                  itemCount: _databases.length,
                                                  itemBuilder: (context, index) {
                                                    final db = _databases[index];
                                                    return Container(
                                                      margin: const EdgeInsets.only(bottom: 12),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(
                                                          color: Colors.grey[300]!,
                                                          width: 1,
                                                        ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black.withOpacity(0.04),
                                                            blurRadius: 8,
                                                            offset: const Offset(0, 2),
                                                          ),
                                                        ],
                                                      ),
                                                      child: Material(
                                                        color: Colors.transparent,
                                                        child: InkWell(
                                                          borderRadius: BorderRadius.circular(12),
                                                          onTap: () => _onDatabaseSelected(db),
                                                          child: Padding(
                                                            padding: const EdgeInsets.all(16),
                                                            child: Row(
                                                              children: [
                                                                Container(
                                                                  padding: const EdgeInsets.all(10),
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFF1E3A8A).withOpacity(0.1),
                                                                    borderRadius: BorderRadius.circular(10),
                                                                  ),
                                                                  child: const Icon(
                                                                    Icons.dns_rounded,
                                                                    color: Color(0xFF1E3A8A),
                                                                    size: 24,
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 16),
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      Text(
                                                                        db.name,
                                                                        style: const TextStyle(
                                                                          fontSize: 16,
                                                                          fontWeight: FontWeight.w600,
                                                                          color: Color(0xFF1F2937),
                                                                        ),
                                                                      ),
                                                                      const SizedBox(height: 4),
                                                                      Row(
                                                                        children: [
                                                                          Icon(
                                                                            Icons.computer_rounded,
                                                                            size: 14,
                                                                            color: Colors.grey[600],
                                                                          ),
                                                                          const SizedBox(width: 4),
                                                                          Expanded(
                                                                            child: Text(
                                                                              'Server: ${db.serverName}',
                                                                              style: TextStyle(
                                                                                fontSize: 13,
                                                                                color: Colors.grey[600],
                                                                              ),
                                                                              overflow: TextOverflow.ellipsis,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 8),
                                                                Container(
                                                                  padding: const EdgeInsets.all(6),
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFF1E3A8A).withOpacity(0.1),
                                                                    borderRadius: BorderRadius.circular(8),
                                                                  ),
                                                                  child: const Icon(
                                                                    Icons.arrow_forward_rounded,
                                                                    color: Color(0xFF1E3A8A),
                                                                    size: 18,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  
                  // Back Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              '/',
                              (route) => false,
                              arguments: {'skipAutoRedirect': true},
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.arrow_back_rounded,
                                  color: Color(0xFF1E3A8A),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Kembali ke Konfigurasi Server',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E3A8A),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}