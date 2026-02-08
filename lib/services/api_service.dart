import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/asset.dart';
import '../models/employee.dart';
import '../models/asset_transfer.dart';
import '../models/maintenance_request.dart';
import '../models/maintenance_calendar_event.dart';
import 'package:flutter/foundation.dart';
import '../models/database_info.dart';
import '../models/category.dart' as model;
import 'cache_service.dart';
import 'auth_service.dart';

class ApiService {
  static String? baseUrl;
  static String? selectedDatabase;
  static String? _sessionId;
  static final http.Client _client = http.Client();
  static int? _uid;
  static bool? _isAssetManagerCache;

  static Future<List<DatabaseInfo>> fetchDatabases(String url) async {
    try {
      // Clean up URL (remove trailing slashes)
      final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      
      // For Odoo 11.0 and above, we need to use JSON-RPC
      final jsonRpcUrl = '$cleanUrl/jsonrpc';
      
      if (kDebugMode) {
        debugPrint('Attempting to fetch databases using JSON-RPC: $jsonRpcUrl');
      }

      // JSON-RPC request body
      final requestBody = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'service': 'db',
          'method': 'list',
          'args': [],
        },
        
        'id': DateTime.now().millisecondsSinceEpoch,
      };
      
      try {
        // Make the POST request to JSON-RPC endpoint
        final response = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode(requestBody),
        ).timeout(const Duration(seconds: 10));

        if (kDebugMode) {
          debugPrint('Response status: ${response.statusCode}');
          debugPrint('Response body: ${response.body}');
        }

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          // Handle JSON-RPC response
          if (data is Map && data.containsKey('result')) {
            final result = data['result'];
            if (result is List) {
              return result.map((dbName) => DatabaseInfo(
                name: dbName.toString(),
                serverName: dbName.toString(),
                managed: false,
              )).toList();
            } else if (result is Map && result.containsKey('databases')) {
              // Handle case where result is an object with 'databases' key
              final databases = result['databases'] as List?;
              if (databases != null) {
                return databases.map((dbName) => DatabaseInfo(
                  name: dbName.toString(),
                  serverName: dbName.toString(),
                  managed: false,
                )).toList();
              }
            }
          }
          
          throw Exception('Format respons tidak dikenali dari server');
        } else {
          throw Exception('Gagal memuat database. Kode status: ${response.statusCode}');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error in JSON-RPC request: $e');
        }
        rethrow;
      }
    } on http.ClientException catch (e) {
      if (kDebugMode) {
        debugPrint('ClientException: $e');
      }
      throw Exception('Tidak dapat terhubung ke server. Pastikan server Odoo berjalan, alamat IP dan port benar, serta perangkat terhubung ke jaringan yang sama. Detail: ${e.message}');
    } on FormatException catch (e) {
      if (kDebugMode) {
        debugPrint('FormatException: $e');
      }
      throw Exception('Format respons tidak valid. Pastikan URL benar dan server merespons dengan format JSON yang benar.');
    } on TimeoutException catch (_) {
      if (kDebugMode) {
        debugPrint('Request timeout');
      }
      throw Exception('Waktu koneksi habis. Pastikan server merespons dengan cepat atau periksa koneksi jaringan Anda.');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Unexpected error: $e');
      }
      if (e.toString().contains('XMLHttpRequest') || e.toString().contains('CORS')) {
        throw Exception('Error CORS: Server memblokir permintaan. Pastikan konfigurasi CORS di server Odoo sudah benar.');
      }
      throw Exception('Terjadi kesalahan: ${e.toString()}');
    }
  }

  static Future<bool> createMaintenanceRequest({
    required int assetId,
    required String title,
    required String description,
    required String maintenanceType,
    required String scheduledDate, // 'YYYY-MM-DD'
    String? scheduledEndDate, // 'YYYY-MM-DD'
    String? priority,
    int? teamId,
    int? userId,
    String? email,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();

    Future<bool> callModel(String model) async {
      final vals = <String, dynamic>{
        'asset_id': assetId,
        'maintenance_request_title': title,
        'description': description,
        'maintenance_type': maintenanceType,
        'scheduled_date': scheduledDate,
      };
      if (scheduledEndDate != null && scheduledEndDate.isNotEmpty) {
        vals['scheduled_end_date'] = scheduledEndDate;
      }
      if (priority != null && priority.isNotEmpty) {
        vals['priority'] = priority;
      }
      if (teamId != null && teamId > 0) {
        vals['team_id'] = teamId;
      }
      if (userId != null && userId > 0) {
        vals['user_id'] = userId;
      }
      if (email != null && email.isNotEmpty) {
        vals['email'] = email;
      }

      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': model,
          'method': 'create',
          'args': [vals],
          'kwargs': {},
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
      if (resp.statusCode != 200) {
        throw Exception('Gagal membuat maintenance request: HTTP ${resp.statusCode}');
      }
      final data = json.decode(resp.body);
      if (data is Map && data['error'] != null) {
        throw Exception('Gagal membuat maintenance request: ${data['error']}');
      }
      return data is Map && data['result'] != null;
    }

    try {
      return await callModel('fits.maintenance.request');
    } catch (_) {
      return await callModel('maintenance.request');
    }
  }

  static Future<bool> updateMaintenanceRequestTeam({
    required int requestId,
    required int teamId,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();

    Future<bool> callModel(String model) async {
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': model,
          'method': 'write',
          'args': [
            [requestId],
            {'team_id': teamId},
          ],
          'kwargs': {},
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
      if (resp.statusCode != 200) {
        throw Exception('Gagal mengubah team maintenance: HTTP ${resp.statusCode}');
      }
      final data = json.decode(resp.body);
      if (data is Map && data['error'] != null) {
        throw Exception('Gagal mengubah team maintenance: ${data['error']}');
      }
      return data is Map && data['result'] == true;
    }

    try {
      return await callModel('fits.maintenance.request');
    } catch (_) {
      return await callModel('maintenance.request');
    }
  }

  static Future<bool> updateMaintenanceState({
    required int requestId,
    required String state,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();

    Future<bool> callModel(String model) async {
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': model,
          'method': 'write',
          'args': [
            [requestId],
            {'state': state},
          ],
          'kwargs': {},
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
      if (resp.statusCode != 200) {
        throw Exception('Gagal mengubah status maintenance: HTTP ${resp.statusCode}');
      }
      final data = json.decode(resp.body);
      if (data is Map && data['error'] != null) {
        throw Exception('Gagal mengubah status maintenance: ${data['error']}');
      }
      return data is Map && data['result'] == true;
    }

    try {
      return await callModel('fits.maintenance.request');
    } catch (_) {
      return await callModel('maintenance.request');
    }
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      if (baseUrl == null || baseUrl!.isEmpty) {
        throw Exception('Base URL is not set');
      }
      
      if (selectedDatabase == null || selectedDatabase!.isEmpty) {
        throw Exception('No database selected');
      }

      // Clean up the base URL by removing any trailing slashes
      final cleanBaseUrl = baseUrl!.endsWith('/') 
          ? baseUrl!.substring(0, baseUrl!.length - 1) 
          : baseUrl!;

      final loginUrl = '$cleanBaseUrl/web/session/authenticate';
      
      if (kDebugMode) {
        debugPrint('Attempting login to database: $selectedDatabase');
        debugPrint('Login URL: $loginUrl');
      }

      final response = await _client.post(
        Uri.parse(loginUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'db': selectedDatabase,
            'login': email,
            'password': password,
          },
          'id': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      if (kDebugMode) {
        debugPrint('Login response status: ${response.statusCode}');
        debugPrint('Login response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Capture session cookie
        final setCookie = response.headers['set-cookie'];
        if (setCookie != null) {
          final match = RegExp(r'session_id=([^;]+)').firstMatch(setCookie);
          if (match != null) {
            _sessionId = match.group(1);
          }
        }
        
        // Check for error in response
        if (responseData['error'] != null) {
          final error = responseData['error'];
          throw Exception('Login failed: ${error['message'] ?? error['data']['message'] ?? 'Unknown error'}');
        }
        
        // Check if login was successful
        if (responseData['result'] == null) {
          throw Exception('Invalid response format from server');
        }
        
        return responseData;
      } else {
        throw Exception('Login failed with status code: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Login error: $e');
      }
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  static Map<String, String> _headersJson() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_sessionId != null && _sessionId!.isNotEmpty) {
      headers['Cookie'] = 'session_id=${_sessionId}';
    }
    return headers;
  }

  static Future<void> ensureSession() async {
    if (_sessionId != null && _sessionId!.isNotEmpty) return;
    // Restore baseUrl and selectedDatabase from prefs
    final cfg = await AuthService.getServerConfig();
    baseUrl = cfg['serverUrl'];
    selectedDatabase = cfg['database'];

    final creds = await AuthService.getCredentials();
    final email = creds['email'] ?? '';
    final password = creds['password'] ?? '';
    if (email.isEmpty || password.isEmpty) return; // nothing to do
    await login(email, password);
  }

  static Future<Map<String, dynamic>> getSessionInfo() async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/session/get_session_info';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {},
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat session info: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is! Map || data['result'] == null) throw Exception('Format session info tidak valid');
    final result = Map<String, dynamic>.from(data['result'] as Map);
    _uid = (result['uid'] is int) ? result['uid'] as int : int.tryParse('${result['uid']}');
    return result;
  }

  static Future<List<Map<String, dynamic>>> getUserGroups({int? uid}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    if (uid == null) {
      await getSessionInfo();
      uid = _uid;
    }
    if (uid == null) throw Exception('User ID tidak ditemukan');
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'res.users',
        'method': 'read',
        'args': [
          [uid],
          ['groups_id']
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat groups: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is! Map || data['result'] == null) throw Exception('Format groups tidak valid');
    final List res = data['result'] as List;
    if (res.isEmpty) return [];
    final m = Map<String, dynamic>.from(res.first as Map);
    // groups_id is m2m; name_get style: list of [id, name]
    final List rawGroups = (m['groups_id'] ?? []) as List;
    final List<int> ids = rawGroups.map<int>((g) {
      if (g is List && g.isNotEmpty) {
        final id = g.first;
        return id is int ? id : int.tryParse('$id') ?? 0;
      }
      return g is int ? g : int.tryParse('$g') ?? 0;
    }).where((e) => e > 0).toList();

    if (ids.isEmpty) return [];

    // Fetch detailed group info to get category name as well
    final groupsBody = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'res.groups',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['id', 'in', ids]
          ],
          'fields': ['id', 'name', 'category_id'],
          'limit': ids.length,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final gResp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(groupsBody));
    if (gResp.statusCode != 200) {
      // Fallback to name_get data if detailed read fails
      return rawGroups.map<Map<String, dynamic>>((g) {
        if (g is List && g.length >= 2) {
          return {'id': g[0], 'name': '${g[1]}'};
        }
        return {'id': g, 'name': '$g'};
      }).toList();
    }
    final gData = json.decode(gResp.body);
    if (gData is! Map || gData['result'] == null) {
      return rawGroups.map<Map<String, dynamic>>((g) {
        if (g is List && g.length >= 2) {
          return {'id': g[0], 'name': '${g[1]}'};
        }
        return {'id': g, 'name': '$g'};
      }).toList();
    }
    final List results = gData['result'] as List;
    return results.map<Map<String, dynamic>>((e) {
      final mm = Map<String, dynamic>.from(e as Map);
      String? catName;
      final cat = mm['category_id'];
      if (cat is List && cat.length >= 2) {
        catName = (cat[1] ?? '').toString();
      } else if (cat is String) {
        catName = cat;
      }
      final name = (mm['name'] ?? '').toString();
      final display = (catName != null && catName.isNotEmpty) ? '$catName / $name' : name;
      return {
        'id': (mm['id'] as num).toInt(),
        'name': name,
        'category_name': catName,
        'display': display,
      };
    }).toList();
  }

  static Future<bool> isAssetManager({bool forceRefresh = false}) async {
    if (!forceRefresh && _isAssetManagerCache != null) return _isAssetManagerCache!;
    try {
      final groups = await getUserGroups();
      // Prefer category-aware detection: category contains 'asset maintenance' and name contains 'manager'
      bool ok = groups.any((g) {
        final cat = (g['category_name'] ?? g['display'] ?? g['name'] ?? '').toString().toLowerCase();
        final name = (g['name'] ?? g['display'] ?? '').toString().toLowerCase();
        final disp = (g['display'] ?? '').toString().toLowerCase();
        final inCat = cat.contains('asset maintenance') || disp.contains('asset maintenance');
        final isMgr = name.contains('manager') || disp.contains('manager');
        return inCat && isMgr;
      });
      // Fallback heuristic: any name contains 'asset' and ('manager' or 'administration')
      if (!ok) {
        ok = groups.any((g) {
          final s = (g['display'] ?? g['name'] ?? '').toString().toLowerCase();
          return s.contains('asset') && (s.contains('manager') || s.contains('administration'));
        });
      }
      _isAssetManagerCache = ok;
      return ok;
    } catch (_) {
      _isAssetManagerCache = false;
      return false;
    }
  }

  static Future<bool> isAssetMaintenanceMember({bool forceRefresh = false}) async {
    try {
      if (forceRefresh) _isAssetManagerCache = null; // ensure fresh session-based groups
      final groups = await getUserGroups();
      // Member if category contains 'asset maintenance' and group name equals 'user' or 'manager'
      return groups.any((g) {
        final cat = (g['category_name'] ?? g['display'] ?? g['name'] ?? '').toString().toLowerCase();
        final name = (g['name'] ?? g['display'] ?? '').toString().toLowerCase();
        final disp = (g['display'] ?? '').toString().toLowerCase();
        final inCat = cat.contains('asset maintenance') || disp.contains('asset maintenance');
        final isUserOrMgr = name == 'user' || name == 'manager' || disp.endsWith('/ user') || disp.endsWith('/ manager');
        return inCat && isUserOrMgr;
      });
    } catch (_) {
      return false;
    }
  }

  static Future<Asset?> fetchAssetByCode(String code) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }

    final cleanBaseUrl = baseUrl!.endsWith('/')
        ? baseUrl!.substring(0, baseUrl!.length - 1)
        : baseUrl!;

    final url = '$cleanBaseUrl/web/dataset/call_kw';

    Future<Asset?> callWithDomain(List<dynamic> domain) async {
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'fits.asset',
          'method': 'search_read',
          'args': [],
          'kwargs': {
            'domain': domain,
            'fields': [
              'id',
              'name',
              'asset_name',
              'serial_number_code',
              'category_id',
              'location_asset_selection',
              'main_asset_selection',
              'status',
              'image_1920',
            ],
            'limit': 1,
          }
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      await ensureSession();
      final response = await _client.post(
        Uri.parse(url),
        headers: _headersJson(),
        body: json.encode(body),
      );
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body);
      if (data is! Map || data['result'] == null) return null;
      final List<dynamic> results = data['result'];
      if (results.isEmpty) return null;
      return Asset.fromJson(results.first as Map<String, dynamic>);
    }

    // Exact match by serial_number_code first
    final byCode = await callWithDomain([
      ['serial_number_code', '=', code],
    ]);
    if (byCode != null) return byCode;

    // Fallback exact match by name OR asset_name
    final byName = await callWithDomain([
      '|',
      ['name', '=', code],
      ['asset_name', '=', code],
    ]);
    return byName;
  }

  static Future<List<model.Category>> fetchAssetCategories({int? limit, int? mainAssetId, bool emptyWhenNoMain = true}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }

    final cleanBaseUrl = baseUrl!.endsWith('/')
        ? baseUrl!.substring(0, baseUrl!.length - 1)
        : baseUrl!;

    final url = '$cleanBaseUrl/web/dataset/call_kw';

    Future<List<model.Category>> callModel(String mdl) async {
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': mdl,
          'method': 'search_read',
          'args': [],
          'kwargs': {
            'domain': mainAssetId != null
                ? [
                    ['main_asset_id', '=', mainAssetId]
                  ]
                : (emptyWhenNoMain
                    ? [
                        ['id', '=', 0]
                      ]
                    : []),
            'fields': ['id', 'name', 'display_name', 'category_code'],
            'context': {'active_test': false},
            if (limit != null && limit > 0) 'limit': limit,
            'order': 'name asc',
          }
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      await ensureSession();
      final response = await _client.post(
        Uri.parse(url),
        headers: _headersJson(),
        body: json.encode(body),
      );

      if (response.statusCode != 200) {
        throw Exception('Gagal memuat kategori: HTTP ${response.statusCode}');
      }
      final data = json.decode(response.body);
      if (data is! Map || data['result'] == null) {
        throw Exception('Format respons kategori tidak valid');
      }
      final List<dynamic> results = data['result'];
      return results
          .map((e) => model.Category.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    try {
      final categories = await callModel('fits.asset.category');
      await CacheService.saveCategories(categories);
      return categories;
    } catch (_) {
      final categories = await callModel('asset.category');
      await CacheService.saveCategories(categories);
      return categories;
    }
  }

  static Future<List<Asset>> fetchAssets({String? query, int limit = 50, int? userId}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }

    final cleanBaseUrl = baseUrl!.endsWith('/')
        ? baseUrl!.substring(0, baseUrl!.length - 1)
        : baseUrl!;

    final url = '$cleanBaseUrl/web/dataset/call_kw';

    // Build domain for search
    dynamic domain;
    final q = (query ?? '').trim();
    final List baseDomain = [];

    int? effectiveUserId = userId;
    if (effectiveUserId == null || effectiveUserId <= 0) {
      try {
        final info = await fetchCurrentUserInfo();
        final role = (info['role'] ?? '').toString();
        if (role == 'User') {
          final dynamic rawUid = info['uid'];
          if (rawUid is int) {
            effectiveUserId = rawUid;
          } else if (rawUid != null) {
            effectiveUserId = int.tryParse(rawUid.toString());
          }
        }
      } catch (_) {}
    }

    if (effectiveUserId != null && effectiveUserId > 0) {
      baseDomain.add(['responsible_person_id.user_id', '=', effectiveUserId]);
    }

    if (q.isEmpty) {
      domain = baseDomain.isEmpty ? [] : baseDomain;
    } else {
      // (name ilike q) OR (asset_name ilike q) OR (serial_number_code ilike q)
      final searchDomain = [
        '|', '|',
        ['name', 'ilike', q],
        ['asset_name', 'ilike', q],
        ['serial_number_code', 'ilike', q],
      ];
      if (baseDomain.isEmpty) {
        domain = searchDomain;
      } else {
        // AND between baseDomain[0] and searchDomain
        domain = ['&', baseDomain.first, ...searchDomain];
      }
    }

    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': domain,
          'fields': [
            'id',
            'name',
            'asset_name',
            'serial_number_code',
            'category_id',
            'location_asset_selection',
            'main_asset_selection',
            'responsible_person_id',
            'status',
            'image_1920',
            'acquisition_date',
          ],
          'limit': limit,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      await ensureSession();
      final response = await _client.post(
        Uri.parse(url),
        headers: _headersJson(),
        body: json.encode(body),
      );

      if (response.statusCode != 200) {
        throw Exception('Gagal memuat aset: HTTP ${response.statusCode}');
      }

      final data = json.decode(response.body);
      if (data is! Map || data['result'] == null) {
        throw Exception('Format respons aset tidak valid');
      }
      final List<dynamic> results = data['result'];
      final assets = results.map((e) => Asset.fromJson(e as Map<String, dynamic>)).toList();
      await CacheService.saveAssets(assets);
      return assets;
    } catch (e) {
      // Fallback to cached assets if available so data doesn't disappear
      final cached = await CacheService.getCachedAssets();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  static Future<List<Employee>> fetchEmployees({String? query, int limit = 50}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/')
        ? baseUrl!.substring(0, baseUrl!.length - 1)
        : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';

    dynamic domain;
    final q = (query ?? '').trim();
    if (q.isEmpty) {
      domain = [];
    } else {
      domain = [
        '|', '|',
        ['name', 'ilike', q],
        ['work_email', 'ilike', q],
        ['work_phone', 'ilike', q],
      ];
    }

    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'hr.employee',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': domain,
          'fields': [
            'id',
            'name',
            'work_email',
            'work_phone',
            'job_id',
            'department_id',
            'parent_id',
            'coach_id',
            'user_id',
            'company_id',
            'image_1920',
          ],
          'limit': limit,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };

    final response = await _client.post(
      Uri.parse(url),
      headers: _headersJson(),
      body: json.encode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat karyawan: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons karyawan tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map((e) => Employee.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<Employee>> fetchEmployeesByIds(List<int> ids) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    if (ids.isEmpty) return [];
    final cleanBaseUrl = baseUrl!.endsWith('/')
        ? baseUrl!.substring(0, baseUrl!.length - 1)
        : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'hr.employee',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['id', 'in', ids]
          ],
          'fields': ['id', 'name', 'work_email', 'work_phone'],
          'limit': ids.length,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat karyawan: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons karyawan tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map((e) => Employee.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<AssetTransfer>> fetchTransfers({String? query, int limit = 50}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/')
        ? baseUrl!.substring(0, baseUrl!.length - 1)
        : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';

    dynamic domain;
    final q = (query ?? '').trim();
    if (q.isEmpty) {
      domain = [];
    } else {
      domain = [
        '|',
        ['name', 'ilike', q],
        ['display_name', 'ilike', q],
      ];
    }

    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset.transfer',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': domain,
          'fields': [
            'id',
            'name',
            'display_name',
            'asset_id',
            'transfer_date',
            'from_location',
            'to_location',
            'to_responsible_person',
            'current_responsible_person',
            'main_asset_name',
            'asset_category_name',
            'location_assets_name',
            'asset_code',
            'reason',
            'state',
          ],
          'limit': limit,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };

    final response = await _client.post(
      Uri.parse(url),
      headers: _headersJson(),
      body: json.encode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat transfer: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons transfer tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map((e) => AssetTransfer.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Map<String, dynamic>> readTransferDetail(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset.transfer',
        'method': 'read',
        'args': [
          [id],
          [
            'id', 'name', 'display_name', 'asset_id', 'transfer_date', 'from_location', 'to_location',
            'main_asset_name', 'asset_category_name', 'location_assets_name', 'asset_code',
            'current_responsible_person', 'to_responsible_person', 'reason', 'state',
            'message_ids', 'message_follower_ids'
          ]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal membaca detail transfer: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons read transfer tidak valid');
    }
    final List res = data['result'] as List;
    if (res.isEmpty) throw Exception('Transfer tidak ditemukan');
    return Map<String, dynamic>.from(res.first as Map);
  }

  static Future<int> createTransfer({
    required int assetId,
    required int toLocationId,
    required int toResponsibleEmployeeId,
    required String reason,
    String? transferDate, // 'YYYY-MM-DD'
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final vals = <String, dynamic>{
      'asset_id': assetId,
      'to_location': toLocationId,
      'to_responsible_person': toResponsibleEmployeeId,
      'reason': reason,
    };
    if (transferDate != null && transferDate.isNotEmpty) {
      vals['transfer_date'] = transferDate;
    }
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset.transfer',
        'method': 'create',
        'args': [vals],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal membuat transfer: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons create transfer tidak valid');
    }
    final newId = data['result'];
    if (newId is int) return newId;
    if (newId is String) return int.tryParse(newId) ?? 0;
    throw Exception('ID transfer baru tidak valid');
  }

  static Future<List<Map<String, dynamic>>> fetchTransferMessages(int transferId, {int limit = 20}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.message',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['model', '=', 'fits.asset.transfer'],
            ['res_id', '=', transferId]
          ],
          'fields': ['id', 'date', 'body', 'author_id', 'message_type', 'subtype_id', 'starred_partner_ids'],
          'order': 'date desc',
          'limit': limit,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat chatter transfer: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons chatter transfer tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.cast<Map<String, dynamic>>();
  }

  static Future<bool> postTransferMessage({
    required int transferId,
    required String body,
    bool isNote = false,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();

    final kwargs = <String, dynamic>{
      'body': body,
      'subtype_xmlid': isNote ? 'mail.mt_note' : 'mail.mt_comment',
    };

    final bodyJson = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset.transfer',
        'method': 'message_post',
        'args': [
          [transferId],
        ],
        'kwargs': kwargs,
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };

    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(bodyJson));
    if (resp.statusCode != 200) {
      throw Exception('Gagal mengirim pesan chatter transfer: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is Map && data['error'] != null) {
      throw Exception('Gagal mengirim pesan chatter transfer: ${data['error']}');
    }
    return true;
  }

  // Fetch reactions for multiple messages, returns list of {message_id, content, partner_id}
  static Future<List<Map<String, dynamic>>> fetchReactionsForMessages(List<int> messageIds) async {
    if (messageIds.isEmpty) return [];
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.message.reaction',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['message_id', 'in', messageIds],
          ],
          'fields': ['id', 'message_id', 'partner_id', 'content'],
          'limit': 1000,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat reactions: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons reactions tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Chatter actions: delete a mail.message
  static Future<bool> deleteMessage(int messageId) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.message',
        'method': 'unlink',
        'args': [[messageId]],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal menghapus pesan: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is Map && data['error'] != null) {
      throw Exception('Gagal menghapus pesan: ${data['error']}');
    }
    return true;
  }

  // Chatter actions: edit a mail.message body (requires rights)
  static Future<bool> editMessage({
    required int messageId,
    required String htmlBody,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.message',
        'method': 'write',
        'args': [
          [messageId],
          {'body': htmlBody},
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal mengedit pesan: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is Map && data['error'] != null) {
      throw Exception('Gagal mengedit pesan: ${data['error']}');
    }
    return data is Map && data['result'] == true;
  }

  // Helper: build a link to open the record in Odoo web
  static String buildRecordLink({
    required String model,
    required int resId,
    int? mailId,
  }) {
    final String base = (baseUrl ?? '').trim();
    final String clean = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final String hash = mailId != null
        ? '#id=$resId&model=$model&view_type=form&mail_id=$mailId'
        : '#id=$resId&model=$model&view_type=form';
    return '$clean/web$hash';
  }

  static Future<bool> submitTransfer(int transferId) async {
    if (baseUrl == null || baseUrl!.isEmpty) throw Exception('Base URL is not set');
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset.transfer',
        'method': 'action_submit',
        'args': [
          [transferId]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) throw Exception('Gagal submit transfer: HTTP ${resp.statusCode}');
    final data = json.decode(resp.body);
    if (data is Map && data['error'] != null) throw Exception('Gagal submit transfer: ${data['error']}');
    return true;
  }

  static Future<bool> approveTransfer(int transferId) async {
    if (baseUrl == null || baseUrl!.isEmpty) throw Exception('Base URL is not set');
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset.transfer',
        'method': 'action_confirm',
        'args': [
          [transferId]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) throw Exception('Gagal approve transfer: HTTP ${resp.statusCode}');
    final data = json.decode(resp.body);
    if (data is Map && data['error'] != null) throw Exception('Gagal approve transfer: ${data['error']}');
    return true;
  }

  static Future<bool> resetTransferToDraft(int transferId) async {
    if (baseUrl == null || baseUrl!.isEmpty) throw Exception('Base URL is not set');
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset.transfer',
        'method': 'action_reset_to_draft',
        'args': [
          [transferId]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) throw Exception('Gagal reset transfer: HTTP ${resp.statusCode}');
    final data = json.decode(resp.body);
    if (data is Map && data['error'] != null) throw Exception('Gagal reset transfer: ${data['error']}');
    return true;
  }

  static Future<bool> createTransferActivity({
    required int transferId,
    required int activityTypeId,
    required String summary,
    String? note,
    String? dueDate,
    int? userId,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    await getSessionInfo();
    final vals = <String, dynamic>{
      'res_model': 'fits.asset.transfer',
      'res_id': transferId,
      'activity_type_id': activityTypeId,
      'summary': summary,
    };
    if (userId != null) {
      vals['user_id'] = userId;
    } else if (_uid != null) {
      vals['user_id'] = _uid;
    }
    if (note != null && note.isNotEmpty) vals['note'] = note;
    if (dueDate != null && dueDate.isNotEmpty) vals['date_deadline'] = dueDate;

    final bodyCreate = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.activity.schedule',
        'method': 'create',
        'args': [vals],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final respCreate = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(bodyCreate));
    if (respCreate.statusCode != 200) {
      throw Exception('Gagal membuat activity transfer: HTTP ${respCreate.statusCode}');
    }
    final dataCreate = json.decode(respCreate.body);
    if (dataCreate is! Map) {
      throw Exception('Format respons create activity transfer tidak valid');
    }
    if (dataCreate['error'] != null) {
      final err = dataCreate['error'];
      if (err is Map) {
        final msg = (err['message'] ?? err['data']?['message'] ?? 'Unknown error').toString();
        throw Exception('Gagal membuat activity transfer: $msg');
      }
      throw Exception('Gagal membuat activity transfer: ${err.toString()}');
    }
    final createdId = dataCreate['result'];
    if (createdId == null) {
      return false;
    }
    final bodyAction = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.activity.schedule',
        'method': 'action_schedule',
        'args': [
          [createdId]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final respAction = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(bodyAction));
    if (respAction.statusCode != 200) {
      throw Exception('Gagal mengkonfirmasi schedule activity transfer: HTTP ${respAction.statusCode}');
    }
    final dataAction = json.decode(respAction.body);
    if (dataAction is Map && dataAction['error'] != null) {
      final err = dataAction['error'];
      if (err is Map) {
        final msg = (err['message'] ?? err['data']?['message'] ?? 'Unknown error').toString();
        throw Exception('Gagal mengkonfirmasi schedule activity transfer: $msg');
      }
      throw Exception('Gagal mengkonfirmasi schedule activity transfer: ${err.toString()}');
    }
    return true;
  }

  static Future<bool> createMaintenanceActivity({
    required int requestId,
    required int activityTypeId,
    required String summary,
    String? note,
    String? dueDate, // 'YYYY-MM-DD'
    int? userId,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    await getSessionInfo();
    final vals = <String, dynamic>{
      'res_model': 'fits.maintenance.request',
      'res_id': requestId,
      'activity_type_id': activityTypeId,
      'summary': summary,
    };
    if (userId != null) {
      vals['user_id'] = userId;
    } else if (_uid != null) {
      vals['user_id'] = _uid;
    }
    if (note != null && note.isNotEmpty) vals['note'] = note;
    if (dueDate != null && dueDate.isNotEmpty) vals['date_deadline'] = dueDate;

    final bodyCreate = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.activity.schedule',
        'method': 'create',
        'args': [vals],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final respCreate = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(bodyCreate));
    if (respCreate.statusCode != 200) {
      throw Exception('Gagal membuat activity maintenance: HTTP ${respCreate.statusCode}');
    }
    final dataCreate = json.decode(respCreate.body);
    if (dataCreate is! Map) {
      throw Exception('Format respons create activity maintenance tidak valid');
    }
    if (dataCreate['error'] != null) {
      final err = dataCreate['error'];
      if (err is Map) {
        final msg = (err['message'] ?? err['data']?['message'] ?? 'Unknown error').toString();
        throw Exception('Gagal membuat activity maintenance: $msg');
      }
      throw Exception('Gagal membuat activity maintenance: ${err.toString()}');
    }
    final createdId = dataCreate['result'];
    if (createdId == null) {
      return false;
    }
    final bodyAction = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.activity.schedule',
        'method': 'action_schedule',
        'args': [
          [createdId]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final respAction = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(bodyAction));
    if (respAction.statusCode != 200) {
      throw Exception('Gagal mengkonfirmasi schedule activity maintenance: HTTP ${respAction.statusCode}');
    }
    final dataAction = json.decode(respAction.body);
    if (dataAction is Map && dataAction['error'] != null) {
      final err = dataAction['error'];
      if (err is Map) {
        final msg = (err['message'] ?? err['data']?['message'] ?? 'Unknown error').toString();
        throw Exception('Gagal mengkonfirmasi schedule activity maintenance: $msg');
      }
      throw Exception('Gagal mengkonfirmasi schedule activity maintenance: ${err.toString()}');
    }
    return true;
  }

  static Future<List<MaintenanceRequest>> fetchMaintenanceRequests({String? query, int? assetId, bool autoGeneratedOnly = false, int limit = 50}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';

    dynamic domain;
    final q = (query ?? '').trim();
    if (q.isEmpty) {
      domain = [];
    } else {
      domain = [
        '|', '|',
        ['maintenance_request_title', 'ilike', q],
        ['description', 'ilike', q],
        ['state', 'ilike', q],
      ];
    }

    if (assetId != null) {
      if (domain is List && domain.isNotEmpty) {
        domain = ['&', ['asset_id', '=', assetId], ...domain];
      } else {
        domain = [
          ['asset_id', '=', assetId],
        ];
      }
    }

    // Batasi data calendar untuk role User: hanya event yang maintenance_responsible_id.user_id = uid
    try {
      final info = await fetchCurrentUserInfo();
      final role = (info['role'] ?? '').toString();
      if (role == 'User') {
        final dynamic rawUid = info['uid'];
        int uid = 0;
        if (rawUid is int) {
          uid = rawUid;
        } else if (rawUid != null) {
          uid = int.tryParse(rawUid.toString()) ?? 0;
        }
        if (uid > 0) {
          final ownerDomain = [
            ['maintenance_responsible_id.user_id', '=', uid],
          ];
          if (domain is List && domain.isNotEmpty) {
            domain = ['&', ownerDomain, ...domain];
          } else {
            domain = ownerDomain;
          }
        }
      }
    } catch (_) {}

    if (autoGeneratedOnly) {
      if (domain is List && domain.isNotEmpty) {
        domain = ['&', ['auto_generated', '=', true], ...domain];
      } else {
        domain = [
          ['auto_generated', '=', true],
        ];
      }
    }

    // Batasi data berdasarkan role User: hanya request yang terkait user / employee terkait user.
    try {
      final info = await fetchCurrentUserInfo();
      final role = (info['role'] ?? '').toString();
      if (role == 'User') {
        final dynamic rawUid = info['uid'];
        int uid = 0;
        if (rawUid is int) {
          uid = rawUid;
        } else if (rawUid != null) {
          uid = int.tryParse(rawUid.toString()) ?? 0;
        }
        if (uid > 0) {
          // Kepemilikan: user_id = uid OR responsible_person_id.user_id = uid
          final ownerDomain = [
            '|',
            ['user_id', '=', uid],
            ['responsible_person_id.user_id', '=', uid],
          ];
          if (domain is List && domain.isNotEmpty) {
            domain = ['&', ownerDomain, ...domain];
          } else {
            domain = ownerDomain;
          }
        }
      }
    } catch (_) {}

    Future<List<MaintenanceRequest>> callModel(String model) async {
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': model,
          'method': 'search_read',
          'args': [],
          'kwargs': {
            'domain': domain,
            'fields': [
              'id',
              'maintenance_request_title',
              'asset_id',
              'description',
              'maintenance_type',
              'state',
              'scheduled_date',
              'scheduled_end_date',
              'user_id',
              'team_id',
              'category_id',
              'location_asset_id',
              'asset_code',
              'responsible_person_id',
              'email',
              'priority',
              'auto_generated',
              'asset_recurrence_pattern',
              'asset_recurrence_interval',
              'asset_recurrence_start_date',
              'asset_recurrence_end_date',
              'asset_next_maintenance_date',
            ],
            'limit': limit,
          }
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
      if (response.statusCode != 200) {
        throw Exception('Gagal memuat maintenance: HTTP ${response.statusCode}');
      }
      final data = json.decode(response.body);
      if (data is! Map || data['result'] == null) {
        throw Exception('Format respons maintenance tidak valid');
      }
      final List<dynamic> results = data['result'];
      return results.map((e) => MaintenanceRequest.fromJson(e as Map<String, dynamic>)).toList();
    }

    try {
      return await callModel('fits.maintenance.request');
    } catch (_) {
      return await callModel('maintenance.request');
    }
  }

  static Future<List<MaintenanceCalendarEvent>> fetchCalendarEvents({String? query, int? assetId, int limit = 100}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';

    dynamic domain;
    final q = (query ?? '').trim();
    if (q.isEmpty) {
      domain = [];
    } else {
      domain = [
        '|',
        ['asset_id', 'ilike', q],
        ['hasil_status', 'ilike', q],
      ];
    }

    if (assetId != null) {
      if (domain is List && domain.isNotEmpty) {
        domain = ['&', ['asset_id', '=', assetId], ...domain];
      } else {
        domain = [
          ['asset_id', '=', assetId],
        ];
      }
    }

    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.maintenance.calendar',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': domain,
          'fields': [
            'id',
            'asset_id',
            'maintenance_date',
            'hasil_status',
            'team_id',
            'maintenance_responsible_id',
            'maintenance_email',
            'description',
            'main_asset_id',
            'asset_category_id',
            'location_asset_id',
            'asset_code',
            'asset_condition',
            'recurrence_start_date',
            'recurrence_end_date',
            'recurrence_interval',
            'recurrence_pattern',
          ],
          'limit': limit,
          'order': 'maintenance_date asc',
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };

    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat calendar: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons calendar tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map((e) => MaintenanceCalendarEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchLocations({int? limit, int? companyId}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.location.assets',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [],
          'fields': ['id', 'location_name', 'location_code'],
          if (limit != null && limit > 0) 'limit': limit,
          'order': 'location_name asc',
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat lokasi: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons lokasi tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map<Map<String, dynamic>>((e) {
      final m = e as Map<String, dynamic>;
      return {
        'id': m['id'] is String ? int.tryParse(m['id']) ?? 0 : (m['id'] ?? 0),
        'name': (m['location_name'] ?? '').toString(),
        'code': (m['location_code'] ?? '').toString(),
      };
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchMainAssets({int? limit, int? companyId}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.main.assets',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [],
          'fields': ['id', 'asset_name', 'asset_code'],
          if (limit != null && limit > 0) 'limit': limit,
          'order': 'asset_name asc',
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat main asset: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons main asset tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map<Map<String, dynamic>>((e) {
      final m = e as Map<String, dynamic>;
      final String aName = (m['asset_name'] ?? '').toString();
      final String aCode = (m['asset_code'] ?? '').toString();
      return {
        'id': m['id'] is String ? int.tryParse(m['id']) ?? 0 : (m['id'] ?? 0),
        'name': aCode.isNotEmpty && aName.isNotEmpty
            ? '$aCode - $aName'
            : (aName.isNotEmpty ? aName : (aCode.isNotEmpty ? aCode : 'Unnamed')),
      };
    }).toList();
  }

  static Future<Map<String, dynamic>> fetchMainAssetDetail(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.main.assets',
        'method': 'read',
        'args': [
          [id],
          ['id', 'asset_name', 'asset_code']
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat detail main asset: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons detail main asset tidak valid');
    }
    final List res = data['result'] as List;
    if (res.isEmpty) throw Exception('Main asset tidak ditemukan');
    return Map<String, dynamic>.from(res.first as Map);
  }

  static Future<int> createMainAsset({
    required String assetName,
    String? assetCode,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final vals = <String, dynamic>{
      'asset_name': assetName,
      if (assetCode != null && assetCode.isNotEmpty) 'asset_code': assetCode,
    };
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.main.assets',
        'method': 'create',
        'args': [vals],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal membuat main asset: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons create main asset tidak valid');
    }
    final newId = data['result'];
    if (newId is int) return newId;
    if (newId is String) return int.tryParse(newId) ?? 0;
    throw Exception('ID main asset baru tidak valid');
  }

  static Future<int> createAsset({
    required String assetName,
    required int categoryId,
    required int locationId,
    int? mainAssetId,
    // optional details
    int? responsiblePersonId,
    int? departmentId,
    String? status,
    String? condition,
    bool? maintenanceRequired,
    String? recurrencePattern,
    String? recurrenceStartDate, // 'YYYY-MM-DD'
    int? recurrenceInterval,
    String? recurrenceEndDate, // 'YYYY-MM-DD'
    String? notes,
    // acquisition & warranty
    String? acquisitionDate, // 'YYYY-MM-DD'
    double? acquisitionCost,
    int? purchaseReferenceId,
    String? warrantyStartDate, // 'YYYY-MM-DD'
    String? warrantyEndDate, // 'YYYY-MM-DD'
    String? warrantyProvider,
    String? warrantyNotes,
    String? imageBase64,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final vals = {
      'asset_name': assetName,
      'category_id': categoryId,
      'location_asset_selection': locationId,
      if (mainAssetId != null) 'main_asset_selection': mainAssetId,
      if (responsiblePersonId != null) 'responsible_person_id': responsiblePersonId,
      if (departmentId != null) 'department_id': departmentId,
      if (status != null && status.isNotEmpty) 'status': status,
      if (condition != null && condition.isNotEmpty) 'condition': condition,
      if (maintenanceRequired != null) 'maintenance_required': maintenanceRequired,
      if (recurrencePattern != null && recurrencePattern.isNotEmpty) 'recurrence_pattern': recurrencePattern,
      if (recurrenceStartDate != null && recurrenceStartDate.isNotEmpty) 'recurrence_start_date': recurrenceStartDate,
      if (recurrenceInterval != null) 'recurrence_interval': recurrenceInterval,
      if (recurrenceEndDate != null && recurrenceEndDate.isNotEmpty) 'recurrence_end_date': recurrenceEndDate,
      if (notes != null) 'notes': notes,
      if (acquisitionDate != null && acquisitionDate.isNotEmpty) 'acquisition_date': acquisitionDate,
      if (acquisitionCost != null) 'acquisition_cost': acquisitionCost,
      if (purchaseReferenceId != null) 'purchase_reference': purchaseReferenceId,
      if (warrantyStartDate != null && warrantyStartDate.isNotEmpty) 'warranty_start_date': warrantyStartDate,
      if (warrantyEndDate != null && warrantyEndDate.isNotEmpty) 'warranty_end_date': warrantyEndDate,
      if (warrantyProvider != null && warrantyProvider.isNotEmpty) 'warranty_provider': warrantyProvider,
      if (warrantyNotes != null && warrantyNotes.isNotEmpty) 'warranty_notes': warrantyNotes,
      if (imageBase64 != null && imageBase64.isNotEmpty) 'image_1920': imageBase64,
    };
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'create',
        'args': [vals],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal membuat aset: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons create aset tidak valid');
    }
    final newId = data['result'];
    if (newId is int) return newId;
    if (newId is String) return int.tryParse(newId) ?? 0;
    throw Exception('ID aset baru tidak valid');
  }

  static Future<int> createAssetCategory({
    required String categoryCode,
    required String name,
    required int mainAssetId,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final vals = {
      'category_code': categoryCode,
      'name': name,
      'main_asset_id': mainAssetId,
    };
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset.category',
        'method': 'create',
        'args': [vals],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal membuat asset category: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons create asset category tidak valid');
    }
    final newId = data['result'];
    if (newId is int) return newId;
    if (newId is String) return int.tryParse(newId) ?? 0;
    throw Exception('ID asset category baru tidak valid');
  }

  static Future<int> createLocation({
    required String locationCode,
    required String locationName,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final vals = {
      'location_code': locationCode,
      'location_name': locationName,
    };
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.location.assets',
        'method': 'create',
        'args': [vals],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal membuat location: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons create location tidak valid');
    }
    final newId = data['result'];
    if (newId is int) return newId;
    if (newId is String) return int.tryParse(newId) ?? 0;
    throw Exception('ID location baru tidak valid');
  }

  static Future<int> createMaintenanceTeam({
    required String name,
    List<int> memberIds = const [],
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final vals = <String, dynamic>{
      'name': name,
      if (memberIds.isNotEmpty) 'member_ids': [
        [6, 0, memberIds]
      ],
    };
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.maintenance.team',
        'method': 'create',
        'args': [vals],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal membuat maintenance team: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons create maintenance team tidak valid');
    }
    final newId = data['result'];
    if (newId is int) return newId;
    if (newId is String) return int.tryParse(newId) ?? 0;
    throw Exception('ID maintenance team baru tidak valid');
  }

  static Future<Map<String, dynamic>> fetchAssetCategoryDetail(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();

    Future<Map<String, dynamic>> callModel(String modelName) async {
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': modelName,
          'method': 'read',
          'args': [
            [id],
            ['id', 'category_code', 'name', 'main_asset_id']
          ],
          'kwargs': {},
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };
      final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
      if (response.statusCode != 200) {
        throw Exception('Gagal memuat detail kategori: HTTP ${response.statusCode}');
      }
      final data = json.decode(response.body);
      if (data is! Map || data['result'] == null) {
        throw Exception('Format respons detail kategori tidak valid');
      }
      final List res = data['result'] as List;
      if (res.isEmpty) throw Exception('Kategori tidak ditemukan');
      return Map<String, dynamic>.from(res.first as Map);
    }

    try {
      return await callModel('fits.asset.category');
    } catch (_) {
      return await callModel('asset.category');
    }
  }

  static Future<Map<String, dynamic>> fetchLocationDetail(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.location.assets',
        'method': 'read',
        'args': [
          [id],
          ['id', 'location_code', 'location_name']
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat detail location: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons detail location tidak valid');
    }
    final List res = data['result'] as List;
    if (res.isEmpty) throw Exception('Location tidak ditemukan');
    return Map<String, dynamic>.from(res.first as Map);
  }

  static Future<Map<String, dynamic>> fetchMaintenanceTeamDetail(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.maintenance.team',
        'method': 'read',
        'args': [
          [id],
          ['id', 'name', 'member_ids', 'active']
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat detail maintenance team: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons detail maintenance team tidak valid');
    }
    final List res = data['result'] as List;
    if (res.isEmpty) throw Exception('Maintenance team tidak ditemukan');
    return Map<String, dynamic>.from(res.first as Map);
  }

  static Future<bool> updateMainAsset({
    required int id,
    String? assetName,
    String? assetCode,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final vals = <String, dynamic>{};
    if (assetName != null) vals['asset_name'] = assetName;
    if (assetCode != null) vals['asset_code'] = assetCode;
    if (vals.isEmpty) return true;
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.main.assets',
        'method': 'write',
        'args': [
          [id],
          vals,
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal update main asset: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons update main asset tidak valid');
    }
    return data['result'] == true;
  }

  static Future<bool> updateAssetCategory({
    required int id,
    String? categoryCode,
    String? name,
    int? mainAssetId,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final vals = <String, dynamic>{};
    if (categoryCode != null) vals['category_code'] = categoryCode;
    if (name != null) vals['name'] = name;
    if (mainAssetId != null) vals['main_asset_id'] = mainAssetId;
    if (vals.isEmpty) return true;
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();

    Future<bool> callModel(String modelName) async {
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': modelName,
          'method': 'write',
          'args': [
            [id],
            vals,
          ],
          'kwargs': {},
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };
      final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
      if (response.statusCode != 200) {
        throw Exception('Gagal update asset category: HTTP ${response.statusCode}');
      }
      final data = json.decode(response.body);
      if (data is Map) {
        if (data['error'] != null) {
          final err = data['error'];
          final msg = (err is Map)
              ? (err['data']?['message'] ?? err['message'] ?? err).toString()
              : err.toString();
          throw Exception('Odoo error: ' + msg);
        }
        if (data['result'] != null) {
          return data['result'] == true;
        }
      }
      throw Exception('Format respons update asset category tidak valid');
    }

    try {
      return await callModel('fits.asset.category');
    } catch (_) {
      return await callModel('asset.category');
    }
  }

  static Future<bool> updateLocation({
    required int id,
    String? locationCode,
    String? locationName,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final vals = <String, dynamic>{};
    if (locationCode != null) vals['location_code'] = locationCode;
    if (locationName != null) vals['location_name'] = locationName;
    if (vals.isEmpty) return true;
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.location.assets',
        'method': 'write',
        'args': [
          [id],
          vals,
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal update location: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons update location tidak valid');
    }
    return data['result'] == true;
  }

  static Future<bool> updateMaintenanceTeam({
    required int id,
    String? name,
    bool? active,
    List<int>? memberIds,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final vals = <String, dynamic>{};
    if (name != null) vals['name'] = name;
    if (active != null) vals['active'] = active;
    if (memberIds != null) {
      vals['member_ids'] = [
        [6, 0, memberIds]
      ];
    }
    if (vals.isEmpty) return true;
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.maintenance.team',
        'method': 'write',
        'args': [
          [id],
          vals,
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal update maintenance team: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons update maintenance team tidak valid');
    }
    return data['result'] == true;
  }

  static Future<bool> deleteMainAsset(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.main.assets',
        'method': 'unlink',
        'args': [
          [id]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal menghapus main asset: HTTP ${response.statusCode}');
    }
    final bodyStr = response.body.trim();
    try {
      final data = json.decode(bodyStr);
      if (data is Map) {
        if (data['error'] != null) {
          throw Exception('Odoo error: ${data['error']}');
        }
        if (data.containsKey('result')) {
          final r = data['result'];
          if (r is bool) return r;
          if (r is num) return r != 0;
        }
      } else if (data is bool) {
        return data;
      }
    } catch (_) {
      // fallthrough to string checks below
    }
    if (bodyStr.toLowerCase() == 'true') return true;
    if (bodyStr.toLowerCase() == 'false') return false;
    throw Exception('Format respons delete main asset tidak valid: '+ bodyStr);
  }

  static Future<bool> deleteAssetCategory(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();

    Future<bool> callModel(String modelName) async {
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': modelName,
          'method': 'unlink',
          'args': [
            [id]
          ],
          'kwargs': {},
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };
      final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
      if (response.statusCode != 200) {
        throw Exception('Gagal menghapus asset category: HTTP ${response.statusCode}');
      }
      final bodyStr = response.body.trim();
      try {
        final data = json.decode(bodyStr);
        if (data is Map) {
          if (data['error'] != null) {
            throw Exception('Odoo error: ${data['error']}');
          }
          if (data.containsKey('result')) {
            final r = data['result'];
            if (r is bool) return r;
            if (r is num) return r != 0;
          }
        } else if (data is bool) {
          return data;
        }
      } catch (_) {}
      if (bodyStr.toLowerCase() == 'true') return true;
      if (bodyStr.toLowerCase() == 'false') return false;
      throw Exception('Format respons delete asset category tidak valid: ' + bodyStr);
    }

    try {
      return await callModel('fits.asset.category');
    } catch (_) {
      return await callModel('asset.category');
    }
  }

  static Future<bool> deleteLocation(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.location.assets',
        'method': 'unlink',
        'args': [
          [id]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal menghapus location: HTTP ${response.statusCode}');
    }
    final bodyStr = response.body.trim();
    try {
      final data = json.decode(bodyStr);
      if (data is Map) {
        if (data['error'] != null) {
          throw Exception('Odoo error: ${data['error']}');
        }
        if (data.containsKey('result')) {
          final r = data['result'];
          if (r is bool) return r;
          if (r is num) return r != 0;
        }
      } else if (data is bool) {
        return data;
      }
    } catch (_) {}
    if (bodyStr.toLowerCase() == 'true') return true;
    if (bodyStr.toLowerCase() == 'false') return false;
    throw Exception('Format respons delete location tidak valid: ' + bodyStr);
  }

  static Future<bool> deleteMaintenanceTeam(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.maintenance.team',
        'method': 'unlink',
        'args': [
          [id]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal menghapus maintenance team: HTTP ${response.statusCode}');
    }
    final bodyStr = response.body.trim();
    try {
      final data = json.decode(bodyStr);
      if (data is Map) {
        if (data['error'] != null) {
          throw Exception('Odoo error: ${data['error']}');
        }
        if (data.containsKey('result')) {
          final r = data['result'];
          if (r is bool) return r;
          if (r is num) return r != 0;
        }
      } else if (data is bool) {
        return data;
      }
    } catch (_) {}
    if (bodyStr.toLowerCase() == 'true') return true;
    if (bodyStr.toLowerCase() == 'false') return false;
    throw Exception('Format respons delete maintenance team tidak valid: ' + bodyStr);
  }

  static Future<Map<String, dynamic>> fetchCurrentUserInfo() async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }

    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;

    await ensureSession();

    // 1) Get session info to know uid and company
    final sessionResp = await _client.post(
      Uri.parse('$cleanBaseUrl/web/session/get_session_info'),
      headers: _headersJson(),
      body: json.encode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {},
        'id': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    if (sessionResp.statusCode != 200) {
      throw Exception('Gagal memuat session info: HTTP ${sessionResp.statusCode}');
    }
    final sessionData = json.decode(sessionResp.body);
    if (sessionData is! Map || sessionData['result'] == null) {
      throw Exception('Format respons session info tidak valid');
    }
    final sess = sessionData['result'] as Map<String, dynamic>;
    final int uid = (sess['uid'] ?? 0) as int;
    final String companyName = (sess['company_name'] ?? '') as String;
    // Prefer login/username from session for consistency with login screen
    final String sessionLogin = ((sess['username'] ?? sess['login']) ?? '').toString();

    // 2) Read user to get email/name and company
    final callKwUrl = '$cleanBaseUrl/web/dataset/call_kw';
    final userBody = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'res.users',
        'method': 'read',
        'args': [
          [uid],
          ['id', 'name', 'login', 'email', 'company_id', 'employee_id']
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final userResp = await _client.post(
      Uri.parse(callKwUrl),
      headers: _headersJson(),
      body: json.encode(userBody),
    );
    if (userResp.statusCode != 200) {
      throw Exception('Gagal memuat data user: HTTP ${userResp.statusCode}');
    }
    final userData = json.decode(userResp.body);
    if (userData is! Map || userData['result'] == null) {
      throw Exception('Format respons user tidak valid');
    }
    final List<dynamic> userList = userData['result'];
    if (userList.isEmpty) {
      throw Exception('User tidak ditemukan');
    }
    final Map<String, dynamic> user = Map<String, dynamic>.from(userList.first as Map);

    int? employeeId;
    if (user['employee_id'] is List && (user['employee_id'] as List).isNotEmpty) {
      final dynamic rawEmployee = (user['employee_id'] as List).first;
      if (rawEmployee is int) {
        employeeId = rawEmployee;
      } else if (rawEmployee != null) {
        employeeId = int.tryParse(rawEmployee.toString());
      }
    }

    String? departmentName;
    if (employeeId != null && employeeId > 0) {
      final employeeBody = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'hr.employee',
          'method': 'read',
          'args': [
            [employeeId],
            ['department_id']
          ],
          'kwargs': {},
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };
      try {
        final empResp = await _client.post(
          Uri.parse(callKwUrl),
          headers: _headersJson(),
          body: json.encode(employeeBody),
        );
        if (empResp.statusCode == 200) {
          final empData = json.decode(empResp.body);
          if (empData is Map && empData['result'] is List && (empData['result'] as List).isNotEmpty) {
            final Map<String, dynamic> emp = Map<String, dynamic>.from((empData['result'] as List).first as Map);
            final dynamic rawDept = emp['department_id'];
            if (rawDept is List && rawDept.length > 1) {
              departmentName = rawDept[1]?.toString();
            } else if (rawDept is String) {
              departmentName = rawDept;
            }
          }
        }
      } catch (_) {
        // ignore employee lookup errors
      }
    }

    // 3) Resolve roles (groups) and map only to: User, Team, Manager
    final groupsBody = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'res.groups',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['users', 'in', [uid]]
          ],
          'fields': ['name', 'category_id'],
        },
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final groupsResp = await _client.post(
      Uri.parse(callKwUrl),
      headers: _headersJson(),
      body: json.encode(groupsBody),
    );
    if (groupsResp.statusCode != 200) {
      throw Exception('Gagal memuat role: HTTP ${groupsResp.statusCode}');
    }
    final groupsData = json.decode(groupsResp.body);
    bool hasUser = false;
    bool hasTeam = false;
    bool hasManager = false;
    if (groupsData is Map && groupsData['result'] is List) {
      for (final g in (groupsData['result'] as List)) {
        final Map<String, dynamic> gm = Map<String, dynamic>.from(g as Map);
        final String gname = (gm['name'] ?? '').toString();
        String catName = '';
        if (gm['category_id'] is List && (gm['category_id'] as List).length > 1) {
          catName = ((gm['category_id'] as List)[1] ?? '').toString();
        }
        // Filter only our module categories
        final bool isAssetMaintenance = catName == 'Asset Maintenance';
        final bool isMaintenanceTeam = catName == 'Maintenance Team';
        if (isAssetMaintenance && gname == 'User') hasUser = true;
        if (isAssetMaintenance && gname == 'Manager') hasManager = true;
        if (isMaintenanceTeam && gname == 'Team') hasTeam = true;
      }
    }

    final resolvedRole = hasManager
        ? 'Manager'
        : (hasTeam
            ? 'Team'
            : (hasUser ? 'User' : 'User'));

    // Persist role so it remains available until logout
    try {
      await AuthService.setUserRole(resolvedRole);
    } catch (_) {}

    return {
      'name': (user['name'] ?? '') as String,
      // Ensure email shown equals the login username
      'email': sessionLogin.isNotEmpty
          ? sessionLogin
          : (((user['login'] ?? '') as String).isNotEmpty
              ? user['login'] as String
              : ((user['email'] ?? '') as String)),
      'company': user['company_id'] is List && (user['company_id'] as List).length > 1
          ? ((user['company_id'] as List)[1]?.toString() ?? companyName)
          : companyName,
      'company_id': user['company_id'] is List && (user['company_id'] as List).isNotEmpty
          ? (((user['company_id'] as List)[0] as num?)?.toInt() ?? 0)
          : 0,
      'role': resolvedRole,
      'department': departmentName ?? '',
    };
  }

  static Future<List<Map<String, dynamic>>> fetchMaintenanceTeams({int? limit}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.maintenance.team',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [],
          'fields': ['id', 'name', 'display_name', 'active'],
          'context': {'active_test': false},
          if (limit != null && limit > 0) 'limit': limit,
          'order': 'name asc',
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat maintenance teams: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons maintenance teams tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map<Map<String, dynamic>>((e) {
      final m = e as Map<String, dynamic>;
      final String nm = ((m['name'] ?? '') as String).isNotEmpty
          ? (m['name'] as String)
          : ((m['display_name'] ?? '').toString());
      return {
        'id': m['id'] is String ? int.tryParse(m['id']) ?? 0 : (m['id'] ?? 0),
        'name': nm,
        'active': (m['active'] ?? false) as bool,
      };
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchPurchaseOrders({int? limit}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'purchase.order',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['state', 'in', ['purchase', 'done']]
          ],
          'fields': ['id', 'name', 'date_order', 'partner_id', 'state'],
          'context': {},
          if (limit != null && limit > 0) 'limit': limit,
          'order': 'date_order desc',
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat purchase orders: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons purchase orders tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map<Map<String, dynamic>>((e) {
      final m = e as Map<String, dynamic>;
      return {
        'id': m['id'] is String ? int.tryParse(m['id']) ?? 0 : (m['id'] ?? 0),
        'name': (m['name'] ?? '') as String,
        'date_order': (m['date_order'] ?? '') as String,
        'partner_id': m['partner_id'] is List && (m['partner_id'] as List).length > 1
            ? ((m['partner_id'] as List)[1]?.toString() ?? '')
            : '',
        'state': (m['state'] ?? '') as String,
      };
    }).toList();
  }

  static Future<bool> generateAssetCode(int assetId) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'generate_code',
        'args': [
          [assetId]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) return false;
    final data = json.decode(response.body);
    if (data is! Map) return false;
    return data['error'] == null;
  }

  static Future<Map<String, dynamic>> readAssetDetail(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'read',
        'args': [
          [id],
          [
            'id', 'name', 'asset_name', 'serial_number_code', 'qr_code_image', 'image_1920',
            'main_asset_selection', 'category_id', 'location_asset_selection', 'status', 'condition',
            'acquisition_date', 'acquisition_cost', 'purchase_reference', 'supplier_id',
            'warranty_start_date', 'warranty_end_date', 'warranty_provider', 'warranty_notes',
            'company_id', 'department_id', 'responsible_person_id', 'notes', 'maintenance_required',
            'recurrence_pattern', 'recurrence_start_date', 'recurrence_interval', 'recurrence_end_date',
            'message_ids', 'message_follower_ids'
          ]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Gagal membaca detail asset: HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons read asset tidak valid');
    }
    final List res = data['result'] as List;
    if (res.isEmpty) throw Exception('Asset tidak ditemukan');
    return Map<String, dynamic>.from(res.first as Map);
  }

  static Future<bool> deleteAsset(int assetId) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'unlink',
        'args': [
          [assetId]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal menghapus aset: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is Map && data['result'] == true) return true;
    if (data is Map && data['error'] != null) {
      throw Exception('Gagal menghapus aset: ${data['error']}');
    }
    return false;
  }

  static Future<bool> canWriteAsset() async {
    if (baseUrl == null || baseUrl!.isEmpty) throw Exception('Base URL is not set');
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'check_access_rights',
        'args': ['write'],
        'kwargs': {'raise_exception': false},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) return false;
    final data = json.decode(resp.body);
    if (data is! Map) return false;
    return data['result'] == true;
  }

  static Future<bool> canUnlinkAsset() async {
    if (baseUrl == null || baseUrl!.isEmpty) throw Exception('Base URL is not set');
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'check_access_rights',
        'args': ['unlink'],
        'kwargs': {'raise_exception': false},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) return false;
    final data = json.decode(resp.body);
    if (data is! Map) return false;
    return data['result'] == true;
  }

  static Future<List<Map<String, dynamic>>> fetchAssetMessages(int assetId, {int limit = 20}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.message',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['model', '=', 'fits.asset'],
            ['res_id', '=', assetId]
          ],
          'fields': ['id', 'date', 'body', 'author_id', 'message_type', 'subtype_id'],
          'order': 'date desc',
          'limit': limit,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat chatter: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons chatter tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.cast<Map<String, dynamic>>();
  }

  static Future<bool> postAssetMessage({
    required int assetId,
    required String body,
    bool isNote = false,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();

    final kwargs = <String, dynamic>{
      'body': body,
    };
    if (isNote) {
      kwargs['subtype_xmlid'] = 'mail.mt_note';
    } else {
      kwargs['subtype_xmlid'] = 'mail.mt_comment';
    }

    final bodyJson = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'message_post',
        'args': [
          [assetId],
        ],
        'kwargs': kwargs,
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };

    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(bodyJson));
    if (resp.statusCode != 200) {
      throw Exception('Gagal mengirim pesan chatter: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is Map && data['error'] != null) {
      throw Exception('Gagal mengirim pesan chatter: ${data['error']}');
    }
    return true;
  }

  static Future<List<Map<String, dynamic>>> fetchMaintenanceMessages(int requestId, {int limit = 20}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.message',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['model', '=', 'fits.maintenance.request'],
            ['res_id', '=', requestId]
          ],
          'fields': ['id', 'date', 'body', 'author_id', 'message_type', 'subtype_id'],
          'order': 'date desc',
          'limit': limit,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat chatter maintenance: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons chatter maintenance tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.cast<Map<String, dynamic>>();
  }

  static Future<bool> postMaintenanceMessage({
    required int requestId,
    required String body,
    bool isNote = false,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();

    final kwargs = <String, dynamic>{
      'body': body,
    };
    kwargs['subtype_xmlid'] = isNote ? 'mail.mt_note' : 'mail.mt_comment';

    final bodyJson = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.maintenance.request',
        'method': 'message_post',
        'args': [
          [requestId],
        ],
        'kwargs': kwargs,
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };

    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(bodyJson));
    if (resp.statusCode != 200) {
      throw Exception('Gagal mengirim pesan chatter maintenance: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is Map && data['error'] != null) {
      throw Exception('Gagal mengirim pesan chatter maintenance: ${data['error']}');
    }
    return true;
  }

  static Future<List<Map<String, dynamic>>> fetchActivityTypes() async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.activity.type',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [],
          'fields': ['id', 'name', 'category'],
          'order': 'name asc',
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat activity types: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons activity types tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchUsers({int limit = 50}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'res.users',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [],
          'fields': ['id', 'name', 'login', 'email'],
          'limit': limit,
          'order': 'name asc',
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat users: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons users tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<bool> createAssetActivity({
    required int assetId,
    required int activityTypeId,
    required String summary,
    String? note,
    String? dueDate, // 'YYYY-MM-DD'
    int? userId,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    await getSessionInfo();
    final vals = <String, dynamic>{
      'res_model': 'fits.asset',
      'res_id': assetId,
      'activity_type_id': activityTypeId,
      'summary': summary,
    };
    if (userId != null) {
      vals['user_id'] = userId;
    } else if (_uid != null) {
      vals['user_id'] = _uid;
    }
    if (note != null && note.isNotEmpty) vals['note'] = note;
    if (dueDate != null && dueDate.isNotEmpty) vals['date_deadline'] = dueDate;

    final bodyCreate = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.activity.schedule',
        'method': 'create',
        'args': [vals],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final respCreate = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(bodyCreate));
    if (respCreate.statusCode != 200) {
      throw Exception('Gagal membuat activity: HTTP ${respCreate.statusCode}');
    }
    final dataCreate = json.decode(respCreate.body);
    if (dataCreate is! Map) {
      throw Exception('Format respons create activity tidak valid');
    }
    if (dataCreate['error'] != null) {
      final err = dataCreate['error'];
      if (err is Map) {
        final msg = (err['message'] ?? err['data']?['message'] ?? 'Unknown error').toString();
        throw Exception('Gagal membuat activity: $msg');
      }
      throw Exception('Gagal membuat activity: ${err.toString()}');
    }
    final createdId = dataCreate['result'];
    if (createdId == null) {
      return false;
    }
    final bodyAction = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.activity.schedule',
        'method': 'action_schedule',
        'args': [
          [createdId]
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final respAction = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(bodyAction));
    if (respAction.statusCode != 200) {
      throw Exception('Gagal mengkonfirmasi schedule activity: HTTP ${respAction.statusCode}');
    }
    final dataAction = json.decode(respAction.body);
    if (dataAction is Map && dataAction['error'] != null) {
      final err = dataAction['error'];
      if (err is Map) {
        final msg = (err['message'] ?? err['data']?['message'] ?? 'Unknown error').toString();
        throw Exception('Gagal mengkonfirmasi schedule activity: $msg');
      }
      throw Exception('Gagal mengkonfirmasi schedule activity: ${err.toString()}');
    }
    return true;
  }

  static Future<List<Map<String, dynamic>>> fetchPartnersByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'res.partner',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['id', 'in', ids]
          ],
          'fields': ['id', 'name', 'email', 'image_128', 'function', 'phone', 'mobile', 'street', 'street2', 'city', 'parent_id'],
          'limit': ids.length,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat partner: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is! Map || data['result'] == null) {
      throw Exception('Format respons partner tidak valid');
    }
    final List<dynamic> results = data['result'];
    return results.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<bool> updateAsset(int id, Map<String, dynamic> values) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'write',
        'args': [
          [id],
          values,
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal update asset: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is Map && data['result'] == true) return true;
    if (data is Map && data['error'] != null) {
      throw Exception('Gagal update asset: ${data['error']}');
    }
    return false;
  }

  static Future<bool> generateMaintenanceSchedule(int id) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'fits.asset',
        'method': 'generate_maintenance_schedule',
        'args': [
          [id],
        ],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gagal generate maintenance schedule: HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    if (data is Map && data['error'] != null) {
      throw Exception('Gagal generate maintenance schedule: ${data['error']}');
    }
    // Odoo button methods typically return an action dict; treat non-error as success
    return true;
  }

  // Resolve current partner_id from current user
  static Future<int> getCurrentPartnerId() async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    await ensureSession();
    await getSessionInfo();
    final int uid = _uid ?? 0;
    if (uid == 0) throw Exception('User not logged in');
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    final body = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'res.users',
        'method': 'read',
        'args': [[uid], ['partner_id']],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(body));
    if (resp.statusCode != 200) throw Exception('Gagal memuat partner_id: HTTP ${resp.statusCode}');
    final data = json.decode(resp.body);
    final List res = (data['result'] ?? []) as List;
    if (res.isEmpty) throw Exception('partner_id tidak ditemukan');
    final m = Map<String, dynamic>.from(res.first as Map);
    final p = m['partner_id'];
    if (p is List && p.isNotEmpty) return (p.first as num).toInt();
    if (p is num) return p.toInt();
    throw Exception('partner_id tidak valid');
  }

  // Toggle star using m2m starred_partner_ids to be compatible across versions
  static Future<bool> toggleMessageStar(int messageId) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final partnerId = await getCurrentPartnerId();
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    // Read current starred_partner_ids
    final readBody = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.message',
        'method': 'read',
        'args': [[messageId], ['starred_partner_ids']],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final r = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(readBody));
    if (r.statusCode != 200) throw Exception('Gagal membaca star: HTTP ${r.statusCode}');
    final rd = json.decode(r.body);
    final List rr = (rd['result'] ?? []) as List;
    List current = rr.isNotEmpty ? (Map.from(rr.first)['starred_partner_ids'] as List? ?? []) : [];
    final bool isStarred = current.map((e) => (e is num) ? e.toInt() : int.tryParse('$e') ?? 0).contains(partnerId);
    final command = isStarred ? [3, partnerId, 0] : [4, partnerId, 0];
    final writeBody = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.message',
        'method': 'write',
        'args': [[messageId], {'starred_partner_ids': [command]}],
        'kwargs': {},
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final w = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(writeBody));
    if (w.statusCode != 200) throw Exception('Gagal toggle star: HTTP ${w.statusCode}');
    final wd = json.decode(w.body);
    if (wd is Map && wd['error'] != null) throw Exception('Gagal toggle star: ${wd['error']}');
    return true;
  }

  // Toggle emoji reaction (available on newer Odoo). Fallback-safe: create or unlink mail.message.reaction
  static Future<bool> toggleReaction({
    required int messageId,
    required String emoji,
  }) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Base URL is not set');
    }
    final partnerId = await getCurrentPartnerId();
    final cleanBaseUrl = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
    final url = '$cleanBaseUrl/web/dataset/call_kw';
    await ensureSession();
    // Search existing reaction
    final searchBody = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'model': 'mail.message.reaction',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': [
            ['message_id', '=', messageId],
            ['partner_id', '=', partnerId],
            ['content', '=', emoji],
          ],
          'fields': ['id'],
          'limit': 1,
        }
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };
    final s = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(searchBody));
    if (s.statusCode != 200) throw Exception('Gagal cek reaction: HTTP ${s.statusCode}');
    final sd = json.decode(s.body);
    final List res = (sd['result'] ?? []) as List;
    if (res.isNotEmpty) {
      final int rid = (Map.from(res.first)['id'] as num).toInt();
      // unlink
      final unlinkBody = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'mail.message.reaction',
          'method': 'unlink',
          'args': [[rid]],
          'kwargs': {},
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };
      final u = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(unlinkBody));
      if (u.statusCode != 200) throw Exception('Gagal hapus reaction: HTTP ${u.statusCode}');
      return true;
    } else {
      // create
      final createBody = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'mail.message.reaction',
          'method': 'create',
          'args': [
            {
              'message_id': messageId,
              'partner_id': partnerId,
              'content': emoji,
            }
          ],
          'kwargs': {},
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };
      final c = await _client.post(Uri.parse(url), headers: _headersJson(), body: json.encode(createBody));
      if (c.statusCode != 200) throw Exception('Gagal buat reaction: HTTP ${c.statusCode}');
      return true;
    }
  }
}
