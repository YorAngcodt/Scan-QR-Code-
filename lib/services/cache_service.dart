import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category.dart';
import '../models/asset.dart';
import '../models/scan_history.dart';
import 'auth_service.dart';

class CacheService {
  static String _buildKey(String base, String serverUrl, String database, String email) {
    final s = (serverUrl).trim();
    final d = (database).trim();
    final e = (email).trim().toLowerCase();
    return '${base}_${s}__${d}__${e}';
  }

  static Future<String> _categoriesKey() async {
    final server = await AuthService.getServerConfig();
    final creds = await AuthService.getCredentials();
    return _buildKey('cached_categories', server['serverUrl'] ?? '', server['database'] ?? '', creds['email'] ?? '');
    
  }
  
  static Future<String> _assetsKey() async {
    final server = await AuthService.getServerConfig();
    final creds = await AuthService.getCredentials();
    return _buildKey('cached_assets', server['serverUrl'] ?? '', server['database'] ?? '', creds['email'] ?? '');
  }

  static Future<String> _historyKey() async {
    final server = await AuthService.getServerConfig();
    final creds = await AuthService.getCredentials();
    return _buildKey('scan_history', server['serverUrl'] ?? '', server['database'] ?? '', creds['email'] ?? '');
  }

  // Categories
  static Future<void> saveCategories(List<Category> categories) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _categoriesKey();
    final jsonList = categories.map((c) => c.toJson()).toList(growable: false);
    await prefs.setString(key, json.encode(jsonList));
  }

  static Future<List<Category>> getCachedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _categoriesKey();
    final jsonString = prefs.getString(key);
    if (jsonString == null || jsonString.isEmpty) return [];
    final List<dynamic> raw = json.decode(jsonString);
    return raw.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList(growable: false);
  }

  static Future<void> clearCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _categoriesKey();
    await prefs.remove(key);
  }

  // Assets
  static Future<void> saveAssets(List<Asset> assets) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _assetsKey();
    final jsonList = assets.map((a) => {
      'id': a.id,
      'asset_name': a.name,
      'name': a.name,
      'serial_number_code': a.code,
      'main_asset_selection': a.mainAsset,
      'category_id': a.category,
      'location_asset_selection': a.location,
      'status': a.status,
      'image_1920': a.imageBase64,
      'image_url': a.imageUrl,
    }).toList(growable: false);
    await prefs.setString(key, json.encode(jsonList));
  }

  static Future<List<Asset>> getCachedAssets() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _assetsKey();
    final jsonString = prefs.getString(key);
    if (jsonString == null || jsonString.isEmpty) return [];
    final List<dynamic> raw = json.decode(jsonString);
    return raw.map((e) => Asset.fromJson(e as Map<String, dynamic>)).toList(growable: false);
  }

  static Future<void> clearAssets() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _assetsKey();
    await prefs.remove(key);
  }

  // Scan History
  static Future<List<ScanHistory>> getScanHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _historyKey();
    final s = prefs.getString(key);
    if (s == null || s.isEmpty) return [];
    final List<dynamic> raw = json.decode(s);
    return raw.map((e) => ScanHistory.fromJson(e as Map<String, dynamic>)).toList(growable: true);
  }

  static Future<void> saveScanHistoryList(List<ScanHistory> items) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _historyKey();
    final jsonList = items.map((h) => h.toJson()).toList(growable: false);
    await prefs.setString(key, json.encode(jsonList));
  }

  static Future<void> addScanHistory(ScanHistory item, {int maxItems = 200}) async {
    final list = await getScanHistory();
    // remove duplicates by assetId and code to keep latest
    list.removeWhere((h) => h.assetId == item.assetId || h.code == item.code);
    list.insert(0, item);
    if (list.length > maxItems) {
      list.removeRange(maxItems, list.length);
    }
    await saveScanHistoryList(list);
  }

  static Future<void> clearScanHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _historyKey();
    await prefs.remove(key);
  }
}
