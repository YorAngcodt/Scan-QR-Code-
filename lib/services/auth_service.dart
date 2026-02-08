import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // User session keys
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _userEmailKey = 'user_email';
  static const String _userNameKey = 'user_name';
  static const String _userRoleKey = 'user_role';
  
  // Server configuration keys
  static const String _serverUrlKey = 'server_url';
  static const String _databaseKey = 'database_name';
  static const String _passwordKey = 'user_password'; // Note: Storing passwords is not recommended for production

  // User session methods
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (await isLoggedIn()) {
      return {
        'email': prefs.getString(_userEmailKey) ?? '',
        'name': prefs.getString(_userNameKey) ?? 'User',
        'role': prefs.getString(_userRoleKey) ?? 'User',
        'serverUrl': prefs.getString(_serverUrlKey),
        'database': prefs.getString(_databaseKey),
      };
    }
    return null;
  }

  static Future<void> setUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userRoleKey, role);
  }

  static Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userRoleKey);
  }

  static Future<void> login({
    required String email,
    required String name,
    required String password,
    required String serverUrl,
    required String database,
    String role = 'User',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, true);
    await prefs.setString(_userEmailKey, email);
    await prefs.setString(_userNameKey, name);
    await prefs.setString(_userRoleKey, role);
    await prefs.setString(_serverUrlKey, serverUrl);
    await prefs.setString(_databaseKey, database);
    await prefs.setString(_passwordKey, password); // Note: In production, use secure storage
  }

  static Future<Map<String, String>> getServerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'serverUrl': prefs.getString(_serverUrlKey) ?? '',
      'database': prefs.getString(_databaseKey) ?? '',
    };
  }

  static Future<Map<String, String>> getCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'email': prefs.getString(_userEmailKey) ?? '',
      'password': prefs.getString(_passwordKey) ?? '',
    };
  }

  static Future<void> saveServerConfig({
    required String serverUrl,
    required String database,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, serverUrl);
    await prefs.setString(_databaseKey, database);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Only clear user session data, keep server URL and database
    await prefs.setBool(_isLoggedInKey, false);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userRoleKey);
    await prefs.remove(_passwordKey);
  }
}
