import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showSuccessAnimation = false;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  late AnimationController _successAnimationController;
  late Animation<double> _successScaleAnimation;
  late Animation<double> _successFadeAnimation;
  late Animation<double> _checkmarkAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize entrance animations
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
    
    // Initialize success animations
    _successAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _successScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 40,
      ),
    ]).animate(_successAnimationController);
    
    _successFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successAnimationController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );
    
    _checkmarkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successAnimationController,
        curve: const Interval(0.4, 0.7, curve: Curves.easeOut),
      ),
    );
    
    _animationController.forward();
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final loggedIn = await AuthService.isLoggedIn();
      if (loggedIn && mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    _successAnimationController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;
      
      if (response['result'] != null) {
        await AuthService.login(
          email: _emailController.text.trim(),
          name: response['result']['name'] ?? 'User',
          role: response['result']['role'] ?? 'User',
          password: _passwordController.text,
          serverUrl: ApiService.baseUrl ?? '',
          database: ApiService.selectedDatabase ?? '',
        );
        
        // Show success animation
        if (mounted) {
          setState(() {
            _isLoading = false;
            _showSuccessAnimation = true;
          });
          
          // Start success animation
          _successAnimationController.forward();
          
          // Navigate after animation completes
          await Future.delayed(const Duration(milliseconds: 2000));
          
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context, 
              '/home',
              (route) => false,
            );
          }
        }
      } else {
        throw Exception('Invalid credentials');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login gagal: ${e.toString()}'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {},
      child: Scaffold(
        body: Stack(
          children: [
            // Main Login Screen
            Container(
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
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                                        Icons.precision_manufacturing_rounded,
                                        size: 60,
                                        color: Color(0xFF1E3A8A),
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 32),
                                  
                                  // Title Section
                                  const Text(
                                    'Asset Maintenance',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Sistem Manajemen Pemeliharaan Aset',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withOpacity(0.9),
                                      letterSpacing: 0.3,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  
                                  const SizedBox(height: 48),
                                  
                                  // Login Form Card
                                  Container(
                                    padding: const EdgeInsets.all(24),
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
                                    child: Form(
                                      key: _formKey,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          const Text(
                                            'Masuk ke Akun Anda',
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1F2937),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Silakan masuk untuk melanjutkan',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 32),
                                          
                                          // Email Field
                                          TextFormField(
                                            controller: _emailController,
                                            decoration: InputDecoration(
                                              labelText: 'Email',
                                              hintText: 'nama@email.com',
                                              prefixIcon: Container(
                                                margin: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1E3A8A).withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.email_outlined,
                                                  color: Color(0xFF1E3A8A),
                                                ),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(color: Colors.grey[300]!),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(color: Colors.grey[300]!),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFF1E3A8A),
                                                  width: 2,
                                                ),
                                              ),
                                              filled: true,
                                              fillColor: Colors.grey[50],
                                            ),
                                            keyboardType: TextInputType.emailAddress,
                                            validator: (value) {
                                              if (value == null || value.isEmpty) {
                                                return 'Silakan masukkan email Anda';
                                              }
                                              if (!value.contains('@') || !value.contains('.')) {
                                                return 'Silakan masukkan email yang valid';
                                              }
                                              return null;
                                            },
                                          ),
                                          
                                          const SizedBox(height: 20),
                                          
                                          // Password Field
                                          TextFormField(
                                            controller: _passwordController,
                                            decoration: InputDecoration(
                                              labelText: 'Password',
                                              hintText: '••••••••',
                                              prefixIcon: Container(
                                                margin: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1E3A8A).withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.lock_outline,
                                                  color: Color(0xFF1E3A8A),
                                                ),
                                              ),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _obscurePassword 
                                                      ? Icons.visibility_outlined 
                                                      : Icons.visibility_off_outlined,
                                                  color: Colors.grey[600],
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    _obscurePassword = !_obscurePassword;
                                                  });
                                                },
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(color: Colors.grey[300]!),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(color: Colors.grey[300]!),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFF1E3A8A),
                                                  width: 2,
                                                ),
                                              ),
                                              filled: true,
                                              fillColor: Colors.grey[50],
                                            ),
                                            obscureText: _obscurePassword,
                                            validator: (value) {
                                              if (value == null || value.isEmpty) {
                                                return 'Silakan masukkan password Anda';
                                              }
                                              if (value.length < 6) {
                                                return 'Password minimal 6 karakter';
                                              }
                                              return null;
                                            },
                                          ),
                                          
                                          const SizedBox(height: 32),
                                          
                                          // Login Button
                                          ElevatedButton(
                                            onPressed: _isLoading ? null : _login,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF1E3A8A),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              elevation: 0,
                                              shadowColor: Colors.transparent,
                                            ),
                                            child: _isLoading
                                                ? const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child: CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.5,
                                                    ),
                                                  )
                                                : const Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Text(
                                                        'Masuk',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.w600,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Icon(Icons.arrow_forward_rounded, size: 20),
                                                    ],
                                                  ),
                                          ),
                                          
                                          const SizedBox(height: 16),
                                          
                                          // Back Button
                                          OutlinedButton(
                                            onPressed: _isLoading ? null : () {
                                              Navigator.pushNamedAndRemoveUntil(
                                                context,
                                                '/databases',
                                                (route) => false,
                                              );
                                            },
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                              side: const BorderSide(
                                                color: Color(0xFF1E3A8A),
                                                width: 1.5,
                                              ),
                                              foregroundColor: const Color(0xFF1E3A8A),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.arrow_back_rounded, size: 20),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Kembali',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 24),
                                  
                                  
                                  const SizedBox(height: 24),
                                ],
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
            
            // Success Animation Overlay
            if (_showSuccessAnimation)
              AnimatedBuilder(
                animation: _successAnimationController,
                builder: (context, child) {
                  return Container(
                    color: Colors.black.withOpacity(0.7 * _successFadeAnimation.value),
                    child: Center(
                      child: FadeTransition(
                        opacity: _successFadeAnimation,
                        child: ScaleTransition(
                          scale: _successScaleAnimation,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Asset Maintenance Icon
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.precision_manufacturing_rounded,
                                      size: 70,
                                      color: Color(0xFF1E3A8A),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Asset\nMaintenance',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF1E3A8A),
                                      ),
                                    ),
                                  ],
                                ),
                                
                                // Checkmark Animation
                                Positioned(
                                  bottom: 20,
                                  right: 20,
                                  child: Transform.scale(
                                    scale: _checkmarkAnimation.value,
                                    child: Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF10B981).withOpacity(0.4),
                                            blurRadius: 15,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 32,
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
                },
              ),
          ],
        ),
      ),
    );
  }
}