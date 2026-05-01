import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const MyApp());
}

void unawaited(Future<void>? future) {}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloud File Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      home: const CloudManagerPage(),
    );
  }
}

/// Real OAuth is enabled by default. Set this to `false` to force demo auth.
/// Provide provider client IDs via dart-defines when using real auth.
class AppConfig {
  static const bool useRealAuth = bool.fromEnvironment(
    'USE_REAL_AUTH',
    defaultValue: true,
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static const String oneDriveClientId = String.fromEnvironment(
    'ONEDRIVE_CLIENT_ID',
    defaultValue: 'c76f0174-f458-4ffe-aa5d-2f38507cde2f',
  );

  static const String dropboxClientId = String.fromEnvironment(
    'DROPBOX_CLIENT_ID',
    defaultValue: '6hkasahy8vzx9ol',
  );

  static const String oauthCallbackScheme = String.fromEnvironment(
    'OAUTH_CALLBACK_SCHEME',
    defaultValue: 'moondrive',
  );

  static const String oauthRedirectUri = String.fromEnvironment(
    'OAUTH_REDIRECT_URI',
    defaultValue: 'moondrive://auth',
  );

  static const String oneDriveRedirectUri = String.fromEnvironment(
    'ONEDRIVE_REDIRECT_URI',
    defaultValue: oauthRedirectUri,
  );

  static const String dropboxRedirectUri = String.fromEnvironment(
    'DROPBOX_REDIRECT_URI',
    defaultValue: 'db-6hkasahy8vzx9ol://oauth2redirect',
  );

}

enum CloudProvider { googleDrive, oneDrive, dropbox }

extension CloudProviderX on CloudProvider {
  String get label {
    switch (this) {
      case CloudProvider.googleDrive:
        return 'Google Drive';
      case CloudProvider.oneDrive:
        return 'OneDrive';
      case CloudProvider.dropbox:
        return 'Dropbox';
    }
  }

  IconData get icon {
    switch (this) {
      case CloudProvider.googleDrive:
        return Icons.workspaces_outline;
      case CloudProvider.oneDrive:
        return Icons.cloud_outlined;
      case CloudProvider.dropbox:
        return Icons.diamond_outlined;
    }
  }

  Color get iconColor {
    switch (this) {
      case CloudProvider.googleDrive:
        return const Color(0xFF2563EB);
      case CloudProvider.oneDrive:
        return const Color(0xFF1D4ED8);
      case CloudProvider.dropbox:
        return const Color(0xFF0EA5E9);
    }
  }

  String get connectSubtitle {
    switch (this) {
      case CloudProvider.googleDrive:
        return 'Connect your Google Drive account';
      case CloudProvider.oneDrive:
        return 'Connect your OneDrive account';
      case CloudProvider.dropbox:
        return 'Connect your Dropbox account';
    }
  }
}

class CloudAccount {
  const CloudAccount({
    required this.provider,
    required this.usedGb,
    required this.totalGb,
    required this.files,
    this.email,
    this.isConnected = false,
    this.token,
    this.refreshToken,
    this.tokenExpiryEpochMs,
    this.lastError,
  });

  final CloudProvider provider;
  final String? email;
  final bool isConnected;
  final String? token;
  final String? refreshToken;
  final int? tokenExpiryEpochMs;
  final String? lastError;
  final double usedGb;
  final double totalGb;
  final List<DriveItem> files;

  String get name => provider.label;
  IconData get icon => provider.icon;
  Color get iconColor => provider.iconColor;

  double get usage {
    if (!isConnected || totalGb == 0) {
      return 0;
    }
    return (usedGb / totalGb).clamp(0.0, 1.0);
  }

  int get usagePercent {
    return (usage * 100).round();
  }

  CloudAccount copyWith({
    String? email,
    bool? isConnected,
    String? token,
    String? refreshToken,
    int? tokenExpiryEpochMs,
    String? lastError,
    double? usedGb,
    double? totalGb,
    List<DriveItem>? files,
    bool clearToken = false,
    bool clearRefreshToken = false,
    bool clearTokenExpiry = false,
    bool clearError = false,
  }) {
    return CloudAccount(
      provider: provider,
      email: email ?? this.email,
      isConnected: isConnected ?? this.isConnected,
      token: clearToken ? null : (token ?? this.token),
      refreshToken: clearRefreshToken ? null : (refreshToken ?? this.refreshToken),
      tokenExpiryEpochMs: clearTokenExpiry
          ? null
          : (tokenExpiryEpochMs ?? this.tokenExpiryEpochMs),
      lastError: clearError ? null : (lastError ?? this.lastError),
      usedGb: usedGb ?? this.usedGb,
      totalGb: totalGb ?? this.totalGb,
      files: files ?? this.files,
    );
  }
}

class DriveItem {
  const DriveItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.trailingInfo,
    required this.icon,
    required this.iconColor,
    this.mimeType,
    this.sizeBytes,
    this.parentIds = const <String>[],
    this.webViewLink,
    this.webContentLink,
  });

  final String? id;
  final String name;
  final String subtitle;
  final String trailingInfo;
  final IconData icon;
  final Color iconColor;
  final String? mimeType;
  final int? sizeBytes;
  final List<String> parentIds;
  final String? webViewLink;
  final String? webContentLink;

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';
}

extension DriveItemX on DriveItem {
  bool get opensExternallyPreferred {
    if (isFolder) {
      return false;
    }

    final lowerMime = (mimeType ?? '').toLowerCase();
    if (lowerMime.contains('wordprocessingml') ||
        lowerMime.contains('msword') ||
        lowerMime.contains('presentationml') ||
        lowerMime.contains('powerpoint') ||
        lowerMime.contains('spreadsheetml') ||
        lowerMime.contains('ms-excel')) {
      return true;
    }

    final lowerName = name.toLowerCase();
    return lowerName.endsWith('.doc') ||
        lowerName.endsWith('.docx') ||
        lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pptx') ||
        lowerName.endsWith('.xls') ||
        lowerName.endsWith('.xlsx');
  }
}

class LoginResult {
  const LoginResult({
    required this.email,
    required this.token,
    required this.usedGb,
    required this.totalGb,
    required this.files,
    this.refreshToken,
    this.tokenExpiryEpochMs,
  });

  final String email;
  final String token;
  final String? refreshToken;
  final int? tokenExpiryEpochMs;
  final double usedGb;
  final double totalGb;
  final List<DriveItem> files;
}

class CloudAuthException implements Exception {
  CloudAuthException(this.message);

  final String message;
}

abstract class CloudAuthService {
  bool requiresPassword(CloudProvider provider);

  Future<LoginResult> login({
    required CloudProvider provider,
    required String email,
    required String password,
  });

  Future<void> disconnect(CloudProvider provider);
}

class FakeCloudAuthService implements CloudAuthService {
  @override
  bool requiresPassword(CloudProvider provider) => true;

  @override
  Future<LoginResult> login({
    required CloudProvider provider,
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final normalizedEmail = email.trim().toLowerCase();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (normalizedEmail.isEmpty) {
      throw CloudAuthException('Storage Email ID is required.');
    }
    if (!emailRegex.hasMatch(normalizedEmail)) {
      throw CloudAuthException('Please enter a valid Storage Email ID.');
    }
    if (password.trim().isEmpty) {
      throw CloudAuthException('Password is required.');
    }
    if (password.trim() != '123456') {
      throw CloudAuthException('Invalid credentials. Demo password is 123456.');
    }

    if (provider == CloudProvider.googleDrive &&
        !normalizedEmail.endsWith('@gmail.com')) {
      throw CloudAuthException('Google Drive requires a gmail.com email ID.');
    }

    if (provider == CloudProvider.oneDrive) {
      final valid =
          normalizedEmail.endsWith('@outlook.com') ||
          normalizedEmail.endsWith('@hotmail.com') ||
          normalizedEmail.endsWith('@live.com');
      if (!valid) {
        throw CloudAuthException(
          'OneDrive requires outlook.com, hotmail.com, or live.com email ID.',
        );
      }
    }

    if (normalizedEmail.contains('error')) {
      throw CloudAuthException('Unable to reach server. Please try again.');
    }

    return LoginResult(
      email: normalizedEmail,
      token: 'token_${provider.name}_${DateTime.now().millisecondsSinceEpoch}',
      tokenExpiryEpochMs:
          DateTime.now().millisecondsSinceEpoch + const Duration(hours: 12).inMilliseconds,
      usedGb: _usedCapacityFor(provider),
      totalGb: _totalCapacityFor(provider),
      files: _filesFor(provider),
    );
  }

  @override
  Future<void> disconnect(CloudProvider provider) async {}

  double _usedCapacityFor(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.googleDrive:
        return 8.5;
      case CloudProvider.oneDrive:
        return 3.2;
      case CloudProvider.dropbox:
        return 1.8;
    }
  }

  double _totalCapacityFor(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.googleDrive:
        return 15;
      case CloudProvider.oneDrive:
        return 5;
      case CloudProvider.dropbox:
        return 2;
    }
  }

  List<DriveItem> _filesFor(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.googleDrive:
        return const [
          DriveItem(
            id: 'demo_google_folder_client_files',
            name: 'Client Files',
            subtitle: 'Folder',
            trailingInfo: 'Mar 10',
            icon: Icons.folder_outlined,
            iconColor: Color(0xFF2563EB),
            mimeType: 'application/vnd.google-apps.folder',
          ),
          DriveItem(
            id: 'demo_google_file_annual_report_docx',
            name: 'Annual Report.docx',
            subtitle: '3.1 MB',
            trailingInfo: 'Mar 21',
            icon: Icons.description_outlined,
            iconColor: Color(0xFF2563EB),
            mimeType:
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          ),
          DriveItem(
            id: 'demo_google_file_invoice_pdf',
            name: 'Invoice_March.pdf',
            subtitle: '680 KB',
            trailingInfo: 'Mar 20',
            icon: Icons.picture_as_pdf_outlined,
            iconColor: Color(0xFFDC2626),
            mimeType: 'application/pdf',
          ),
          DriveItem(
            id: 'demo_google_file_team_photo_jpg',
            name: 'Team_Photo.jpg',
            subtitle: '2.8 MB',
            trailingInfo: 'Mar 19',
            icon: Icons.image_outlined,
            iconColor: Color(0xFF16A34A),
            mimeType: 'image/jpeg',
          ),
        ];
      case CloudProvider.oneDrive:
        return const [
          DriveItem(
            id: 'demo_onedrive_folder_work_documents',
            name: 'Work_Documents',
            subtitle: 'Folder',
            trailingInfo: 'Yesterday',
            icon: Icons.folder_outlined,
            iconColor: Color(0xFF1D4ED8),
            mimeType: 'application/vnd.google-apps.folder',
          ),
          DriveItem(
            id: 'demo_onedrive_file_invoices_pdf',
            name: 'Invoices_2026.pdf',
            subtitle: '900 KB',
            trailingInfo: 'Mar 20',
            icon: Icons.receipt_long_outlined,
            iconColor: Color(0xFF0891B2),
            mimeType: 'application/pdf',
          ),
          DriveItem(
            id: 'demo_onedrive_file_roadmap_docx',
            name: 'Roadmap.docx',
            subtitle: '2.1 MB',
            trailingInfo: 'Mar 19',
            icon: Icons.description_outlined,
            iconColor: Color(0xFF1D4ED8),
            mimeType:
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          ),
        ];
      case CloudProvider.dropbox:
        return const [
          DriveItem(
            id: 'demo_dropbox_folder_archive',
            name: 'Archive',
            subtitle: 'Folder',
            trailingInfo: 'Mar 16',
            icon: Icons.folder_zip_outlined,
            iconColor: Color(0xFF0EA5E9),
            mimeType: 'application/vnd.google-apps.folder',
          ),
          DriveItem(
            id: 'demo_dropbox_file_design_fig',
            name: 'Design_System.fig',
            subtitle: '4.4 MB',
            trailingInfo: 'Mar 21',
            icon: Icons.draw_outlined,
            iconColor: Color(0xFF0EA5E9),
            mimeType: 'application/octet-stream',
          ),
          DriveItem(
            id: 'demo_dropbox_file_client_brief_pdf',
            name: 'Client_Brief.pdf',
            subtitle: '780 KB',
            trailingInfo: 'Today',
            icon: Icons.picture_as_pdf_outlined,
            iconColor: Color(0xFFDC2626),
            mimeType: 'application/pdf',
          ),
        ];
    }
  }
}

/// Placeholder for real OAuth-based auth. Wire provider SDKs + OAuth tokens
/// here, then flip `AppConfig.useRealAuth` to true.
class RealCloudAuthService implements CloudAuthService {
    RealCloudAuthService()
    : _googleSignIn = GoogleSignIn(
        scopes: const <String>['email', drive.DriveApi.driveFileScope],
        serverClientId: AppConfig.googleServerClientId.isEmpty
            ? null
            : AppConfig.googleServerClientId,
      );
    final GoogleSignIn _googleSignIn;

  FlutterWebAuth2Options _oauthAuthOptions() {
    return const FlutterWebAuth2Options(
      preferEphemeral: true,
      intentFlags: ephemeralIntentFlags,
      customTabsPackageOrder: <String>[
        'com.android.chrome',
        'com.chrome.beta',
        'com.chrome.dev',
        'com.microsoft.emmx',
        'org.mozilla.firefox',
      ],
    );
  }

  @override
  bool requiresPassword(CloudProvider provider) {
    return false;
  }

  @override
  Future<void> disconnect(CloudProvider provider) async {
    if (provider == CloudProvider.googleDrive) {
      await _googleSignIn.signOut();
    }
  }

  @override
  Future<LoginResult> login({
    required CloudProvider provider,
    required String email,
    required String password,
  }) async {
    switch (provider) {
      case CloudProvider.googleDrive:
        return _loginGoogleDrive();
      case CloudProvider.oneDrive:
        return _loginOneDrive();
      case CloudProvider.dropbox:
        return _loginDropbox();
    }
  }

  Future<LoginResult> _loginOneDrive() async {
    if (AppConfig.oneDriveClientId.isEmpty) {
      throw CloudAuthException(
        'OneDrive is not configured. Add ONEDRIVE_CLIENT_ID in dart-defines.',
      );
    }

    final redirectUri = _parseRedirectUriOrThrow(
      AppConfig.oneDriveRedirectUri,
      providerName: 'OneDrive',
      configKey: 'ONEDRIVE_REDIRECT_URI',
    );
    final callbackScheme = _callbackSchemeForRedirect(
      redirectUri,
      providerName: 'OneDrive',
      configKey: 'ONEDRIVE_REDIRECT_URI',
    );

    final state = _randomUrlSafe(24);
    final verifier = _randomUrlSafe(64);
    final challenge = _toBase64UrlNoPadding(
      sha256.convert(utf8.encode(verifier)).bytes,
    );
    final callbackUri = await FlutterWebAuth2.authenticate(
      url: Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/authorize', {
        'client_id': AppConfig.oneDriveClientId,
        'response_type': 'code',
        'redirect_uri': redirectUri.toString(),
        'response_mode': 'query',
        'scope': 'offline_access openid profile email User.Read Files.Read Files.ReadWrite',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      }).toString(),
      callbackUrlScheme: callbackScheme,
      options: _oauthAuthOptions(),
    );

    final callback = Uri.parse(callbackUri);
    final callbackParams = _extractOAuthParams(callback);
    if (callbackParams['state'] != state) {
      throw CloudAuthException('OneDrive login failed: invalid OAuth state.');
    }
    final authError = _formatOAuthError(callbackParams);
    if (authError != null) {
      throw CloudAuthException('OneDrive login failed: $authError');
    }

    final code = callbackParams['code'];
    if (code == null || code.isEmpty) {
      throw CloudAuthException('OneDrive login canceled or code not returned.');
    }

    final tokenResponse = await http.post(
      Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: <String, String>{
        'client_id': AppConfig.oneDriveClientId,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri.toString(),
        'code': code,
        'code_verifier': verifier,
      },
    );

    final tokenPayload = _decodeJsonMap(tokenResponse.body);
    if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
      throw CloudAuthException(
        'OneDrive token exchange failed (${tokenResponse.statusCode}): ${tokenPayload['error_description'] ?? tokenPayload['error'] ?? 'unknown error'}',
      );
    }

    final accessToken = (tokenPayload['access_token'] as String?) ?? '';
    final refreshToken = (tokenPayload['refresh_token'] as String?)?.trim();
    final expiresIn = _toInt(tokenPayload['expires_in']);
    final expiryEpochMs = DateTime.now().millisecondsSinceEpoch +
        ((expiresIn > 0 ? expiresIn : 3600) * 1000) -
        const Duration(minutes: 2).inMilliseconds;
    if (accessToken.isEmpty) {
      throw CloudAuthException('OneDrive access token not returned.');
    }

    final client = _AccessTokenClient(accessToken);
    try {
      final meResponse = await client.get(
        Uri.https('graph.microsoft.com', '/v1.0/me', {
          r'$select': 'mail,userPrincipalName',
        }),
      );
      final driveResponse = await client.get(
        Uri.https('graph.microsoft.com', '/v1.0/me/drive', {
          r'$select': 'quota',
        }),
      );
      final childrenResponse = await client.get(
        Uri.https('graph.microsoft.com', '/v1.0/me/drive/root/children', {
          r'$top': '30',
          r'$select':
              'id,name,size,file,folder,lastModifiedDateTime,webUrl',
        }),
      );

      if (meResponse.statusCode >= 300 ||
          driveResponse.statusCode >= 300 ||
          childrenResponse.statusCode >= 300) {
        throw CloudAuthException('OneDrive API request failed.');
      }

      final me = _decodeJsonMap(meResponse.body);
      final driveInfo = _decodeJsonMap(driveResponse.body);
      final children = _decodeJsonMap(childrenResponse.body);

      final quota = (driveInfo['quota'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final usedBytes = _toInt(quota['used']);
      final totalBytes = _toInt(quota['total']);
      final items = (children['value'] as List?) ?? const <dynamic>[];

      return LoginResult(
        email:
            (me['mail'] as String?) ??
            (me['userPrincipalName'] as String?) ??
            'onedrive_user',
        token: accessToken,
        refreshToken:
            (refreshToken == null || refreshToken.isEmpty) ? null : refreshToken,
        tokenExpiryEpochMs: expiryEpochMs,
        usedGb: _bytesToGb(usedBytes),
        totalGb: totalBytes > 0 ? _bytesToGb(totalBytes) : 5,
        files: items
            .whereType<Map>()
            .map((raw) => raw.cast<String, dynamic>())
            .map(_mapOneDriveItem)
            .toList(),
      );
    } finally {
      client.close();
    }
  }

  Future<LoginResult> _loginDropbox() async {
    if (AppConfig.dropboxClientId.isEmpty) {
      throw CloudAuthException(
        'Dropbox is not configured. Add DROPBOX_CLIENT_ID in dart-defines.',
      );
    }

    final redirectUri = _parseRedirectUriOrThrow(
      AppConfig.dropboxRedirectUri,
      providerName: 'Dropbox',
      configKey: 'DROPBOX_REDIRECT_URI',
    );
    final callbackScheme = _callbackSchemeForRedirect(
      redirectUri,
      providerName: 'Dropbox',
      configKey: 'DROPBOX_REDIRECT_URI',
    );

    final state = _randomUrlSafe(24);
    final verifier = _randomUrlSafe(64);
    final challenge = _toBase64UrlNoPadding(
      sha256.convert(utf8.encode(verifier)).bytes,
    );

    final callbackUri = await FlutterWebAuth2.authenticate(
      url: Uri.https('www.dropbox.com', '/oauth2/authorize', {
        'client_id': AppConfig.dropboxClientId,
        'response_type': 'code',
        'redirect_uri': redirectUri.toString(),
        'token_access_type': 'offline',
        'scope':
            'account_info.read files.metadata.read files.content.read files.content.write',
        'include_granted_scopes': 'user',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      }).toString(),
      callbackUrlScheme: callbackScheme,
      options: _oauthAuthOptions(),
    );

    final callback = Uri.parse(callbackUri);
    final callbackParams = _extractOAuthParams(callback);
    if (callbackParams['state'] != state) {
      throw CloudAuthException('Dropbox login failed: invalid OAuth state.');
    }
    final authError = _formatOAuthError(callbackParams);
    if (authError != null) {
      throw CloudAuthException('Dropbox login failed: $authError');
    }

    final code = callbackParams['code'];
    if (code == null || code.isEmpty) {
      throw CloudAuthException('Dropbox login canceled or code not returned.');
    }

    final tokenResponse = await http.post(
      Uri.https('api.dropboxapi.com', '/oauth2/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: <String, String>{
        'client_id': AppConfig.dropboxClientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri.toString(),
        'code_verifier': verifier,
      },
    );

    final tokenPayload = _decodeJsonMap(tokenResponse.body);
    if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
      throw CloudAuthException(
        'Dropbox token exchange failed (${tokenResponse.statusCode}): ${tokenPayload['error_description'] ?? tokenPayload['error'] ?? 'unknown error'}',
      );
    }

    final accessToken = (tokenPayload['access_token'] as String?) ?? '';
    final refreshToken = (tokenPayload['refresh_token'] as String?)?.trim();
    final expiresIn = _toInt(tokenPayload['expires_in']);
    final expiryEpochMs = DateTime.now().millisecondsSinceEpoch +
        ((expiresIn > 0 ? expiresIn : 3600) * 1000) -
        const Duration(minutes: 2).inMilliseconds;
    if (accessToken.isEmpty) {
      throw CloudAuthException('Dropbox access token not returned.');
    }

    final client = _AccessTokenClient(accessToken);
    try {
      final accountResponse = await client.post(
        Uri.https('api.dropboxapi.com', '/2/users/get_current_account'),
        headers: const {'Content-Type': 'application/json'},
        body: 'null',
      );
      final usageResponse = await client.post(
        Uri.https('api.dropboxapi.com', '/2/users/get_space_usage'),
        headers: const {'Content-Type': 'application/json'},
        body: 'null',
      );
      var listResponse = await client.post(
        Uri.https('api.dropboxapi.com', '/2/files/list_folder'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(
          const {
            'path': '',
            'recursive': false,
            'include_deleted': false,
            'limit': 30,
          },
        ),
      );

      // Some app-folder configurations reject empty path; fallback to root slash.
      if (listResponse.statusCode >= 300) {
        listResponse = await client.post(
          Uri.https('api.dropboxapi.com', '/2/files/list_folder'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(
            const {
              'path': '/',
              'recursive': false,
              'include_deleted': false,
              'limit': 30,
            },
          ),
        );
      }

      if (accountResponse.statusCode >= 300) {
        throw CloudAuthException(
          'Dropbox account request failed: ${_formatDropboxHttpError(accountResponse)}',
        );
      }
      if (listResponse.statusCode >= 300) {
        throw CloudAuthException(
          'Dropbox file listing failed: ${_formatDropboxHttpError(listResponse)}',
        );
      }

      final accountInfo = _decodeJsonMap(accountResponse.body);
      final listInfo = _decodeJsonMap(listResponse.body);

      Map<String, dynamic> usageInfo = const <String, dynamic>{};
      if (usageResponse.statusCode >= 200 && usageResponse.statusCode < 300) {
        usageInfo = _decodeJsonMap(usageResponse.body);
      }

      final usedBytes = _toInt(usageInfo['used']);
      final allocation =
          (usageInfo['allocation'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final totalBytes = _toInt(allocation['allocated']);
      final entries = (listInfo['entries'] as List?) ?? const <dynamic>[];

      return LoginResult(
        email: (accountInfo['email'] as String?) ?? 'dropbox_user',
        token: accessToken,
        refreshToken:
            (refreshToken == null || refreshToken.isEmpty) ? null : refreshToken,
        tokenExpiryEpochMs: expiryEpochMs,
        usedGb: _bytesToGb(usedBytes),
        totalGb: totalBytes > 0 ? _bytesToGb(totalBytes) : 2,
        files: entries
            .whereType<Map>()
            .map((raw) => raw.cast<String, dynamic>())
            .map(_mapDropboxItem)
            .toList(),
      );
    } finally {
      client.close();
    }
  }

  String _formatDropboxHttpError(http.Response response) {
    final body = response.body;
    if (body.trim().isEmpty) {
      return 'HTTP ${response.statusCode}';
    }

    try {
      final decoded = _decodeJsonMap(body);
      final summary =
          decoded['error_summary'] ??
          decoded['error_description'] ??
          decoded['error'];
      if (summary != null && summary.toString().trim().isNotEmpty) {
        return 'HTTP ${response.statusCode}: $summary';
      }
    } catch (_) {
      // Keep raw body fallback below when response is not JSON.
    }

    final compactBody = body.length > 220 ? '${body.substring(0, 220)}...' : body;
    return 'HTTP ${response.statusCode}: $compactBody';
  }

  DriveItem _mapOneDriveItem(Map<String, dynamic> item) {
    final isFolder = item['folder'] != null;
    final modified = DateTime.tryParse((item['lastModifiedDateTime'] as String?) ?? '');
    final size = _toInt(item['size']);
    final fileMeta = (item['file'] as Map?)?.cast<String, dynamic>();
    final mimeType = isFolder
        ? 'application/vnd.google-apps.folder'
        : ((fileMeta?['mimeType'] as String?) ??
              _guessMimeTypeByName((item['name'] as String?) ?? ''));

    return DriveItem(
      id: item['id'] as String?,
      name: (item['name'] as String?) ?? 'Untitled',
      subtitle: isFolder ? 'Folder' : _formatBytes(size),
      trailingInfo: _formatModifiedDate(modified),
      icon: _iconForMimeType(mimeType, isFolder: isFolder),
      iconColor: _colorForMimeType(mimeType, isFolder: isFolder),
      mimeType: mimeType,
      sizeBytes: isFolder ? null : size,
      webViewLink: item['webUrl'] as String?,
      webContentLink: item['webUrl'] as String?,
    );
  }

  DriveItem _mapDropboxItem(Map<String, dynamic> item) {
    final tag = item['.tag'] as String?;
    final isFolder = tag == 'folder';
    final modified = DateTime.tryParse((item['server_modified'] as String?) ?? '');
    final size = _toInt(item['size']);
    final name = (item['name'] as String?) ?? 'Untitled';
    final mimeType = isFolder
        ? 'application/vnd.google-apps.folder'
        : _guessMimeTypeByName(name);

    return DriveItem(
      id: (item['path_lower'] as String?) ?? (item['id'] as String?),
      name: name,
      subtitle: isFolder ? 'Folder' : _formatBytes(size),
      trailingInfo: _formatModifiedDate(modified),
      icon: _iconForMimeType(mimeType, isFolder: isFolder),
      iconColor: _colorForMimeType(mimeType, isFolder: isFolder),
      mimeType: mimeType,
      sizeBytes: isFolder ? null : size,
      webViewLink: null,
      webContentLink: null,
    );
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  Uri _parseRedirectUriOrThrow(
    String raw, {
    required String providerName,
    required String configKey,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw CloudAuthException(
        '$providerName redirect URI is empty. Set $configKey in dart-defines.',
      );
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.trim().isEmpty) {
      throw CloudAuthException(
        '$providerName redirect URI is invalid. Check $configKey.',
      );
    }
    return uri;
  }

  String _callbackSchemeForRedirect(
    Uri redirectUri, {
    required String providerName,
    required String configKey,
  }) {
    final scheme = redirectUri.scheme.trim().toLowerCase();
    if (scheme.isEmpty || scheme == 'http' || scheme == 'https') {
      throw CloudAuthException(
        '$providerName redirect URI must use a custom app scheme for mobile callback. Update $configKey.',
      );
    }
    return scheme;
  }

  Map<String, String> _extractOAuthParams(Uri uri) {
    if (uri.queryParameters.isNotEmpty) {
      return uri.queryParameters;
    }
    if (uri.fragment.isEmpty) {
      return const <String, String>{};
    }
    return Uri.splitQueryString(uri.fragment);
  }

  String? _formatOAuthError(Map<String, String> parameters) {
    final error = parameters['error'];
    final description = parameters['error_description'];
    if (description != null && description.trim().isNotEmpty) {
      return description;
    }
    if (error != null && error.trim().isNotEmpty) {
      return error;
    }
    return null;
  }

  String _guessMimeTypeByName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.wmv') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.mpg') ||
        lower.endsWith('.mpeg') ||
        lower.endsWith('.ts')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.m4a')) {
      return 'audio/mpeg';
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return 'text/plain';
    }
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
      return 'application/zip';
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    return 'application/octet-stream';
  }

  String _randomUrlSafe(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  String _toBase64UrlNoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<LoginResult> _loginGoogleDrive() async {
    GoogleSignInAccount? account;

    try {
      account = await _googleSignIn.signInSilently();
      account ??= await _googleSignIn.signIn();
    } catch (e) {
      throw CloudAuthException(
        'Google Sign-In failed. Verify SHA-1/SHA-256, OAuth client setup, and try again. Details: $e',
      );
    }

    if (account == null) {
      throw CloudAuthException('Google Sign-In was canceled.');
    }

    final auth = await account.authentication;
    final accessToken = auth.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      throw CloudAuthException(
        'Google access token not available. Check OAuth consent and Drive scope permissions.',
      );
    }

    final client = _AccessTokenClient(accessToken);
    try {
      final api = drive.DriveApi(client);

      final about = await api.about.get(
        $fields: 'user(emailAddress),storageQuota(limit,usage)',
      );

      final filesResponse = await api.files.list(
        q: "trashed = false and 'root' in parents",
        pageSize: 30,
        orderBy: 'modifiedTime desc',
        $fields:
            'files(id,name,mimeType,size,modifiedTime,parents,webViewLink,webContentLink)',
      );

      final usageBytes = int.tryParse(about.storageQuota?.usage ?? '0') ?? 0;
      final limitBytes = int.tryParse(about.storageQuota?.limit ?? '0') ?? 0;

      return LoginResult(
        email: about.user?.emailAddress ?? account.email,
        token: accessToken,
        tokenExpiryEpochMs:
            DateTime.now().millisecondsSinceEpoch +
            const Duration(minutes: 50).inMilliseconds,
        usedGb: _bytesToGb(usageBytes),
        totalGb: limitBytes > 0 ? _bytesToGb(limitBytes) : 15,
        files: _toDriveItems(filesResponse.files),
      );
    } finally {
      client.close();
    }
  }

  List<DriveItem> _toDriveItems(List<drive.File>? files) {
    if (files == null || files.isEmpty) {
      return const [];
    }

    return files.map((file) {
      final isFolder = file.mimeType == 'application/vnd.google-apps.folder';
      final parsedSize = int.tryParse(file.size ?? '0') ?? 0;
      final subtitle = isFolder ? 'Folder' : _formatBytes(parsedSize);

      return DriveItem(
        id: file.id,
        name: (file.name == null || file.name!.trim().isEmpty)
            ? 'Untitled'
            : file.name!,
        subtitle: subtitle,
        trailingInfo: _formatModifiedDate(file.modifiedTime),
        icon: _iconForMimeType(file.mimeType, isFolder: isFolder),
        iconColor: _colorForMimeType(file.mimeType, isFolder: isFolder),
        mimeType: file.mimeType,
        sizeBytes: isFolder ? null : parsedSize,
        parentIds: List<String>.from(file.parents ?? const <String>[]),
        webViewLink: file.webViewLink,
        webContentLink: file.webContentLink,
      );
    }).toList();
  }

  IconData _iconForMimeType(String? mimeType, {required bool isFolder}) {
    if (isFolder) {
      return Icons.folder_outlined;
    }
    final type = (mimeType ?? '').toLowerCase();
    if (type.contains('pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (type.contains('spreadsheet') ||
        type.contains('excel') ||
        type.contains('sheet')) {
      return Icons.table_chart_outlined;
    }
    if (type.contains('presentation') || type.contains('powerpoint')) {
      return Icons.present_to_all_outlined;
    }
    if (type.contains('image')) {
      return Icons.image_outlined;
    }
    if (type.contains('video')) {
      return Icons.videocam_outlined;
    }
    if (type.contains('audio')) {
      return Icons.audiotrack_outlined;
    }
    return Icons.description_outlined;
  }

  Color _colorForMimeType(String? mimeType, {required bool isFolder}) {
    if (isFolder) {
      return const Color(0xFF2563EB);
    }
    final type = (mimeType ?? '').toLowerCase();
    if (type.contains('pdf')) {
      return const Color(0xFFDC2626);
    }
    if (type.contains('spreadsheet') ||
        type.contains('excel') ||
        type.contains('sheet')) {
      return const Color(0xFF16A34A);
    }
    if (type.contains('presentation') || type.contains('powerpoint')) {
      return const Color(0xFFEA580C);
    }
    if (type.contains('image')) {
      return const Color(0xFF059669);
    }
    if (type.contains('video')) {
      return const Color(0xFF7C3AED);
    }
    if (type.contains('audio')) {
      return const Color(0xFF0284C7);
    }
    return const Color(0xFF1D4ED8);
  }

  String _formatModifiedDate(DateTime? modifiedTime) {
    if (modifiedTime == null) {
      return 'Recently';
    }
    final now = DateTime.now();
    final date = modifiedTime.toLocal();
    final difference = now.difference(date).inDays;

    if (difference <= 0) {
      return 'Today';
    }
    if (difference == 1) {
      return 'Yesterday';
    }

    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(1)} GB';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  double _bytesToGb(int bytes) {
    const bytesPerGb = 1024 * 1024 * 1024;
    return bytes <= 0 ? 0 : bytes / bytesPerGb;
  }
}

class _AccessTokenClient extends http.BaseClient {
  _AccessTokenClient(this._accessToken);

  final String _accessToken;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}

class CloudManagerPage extends StatefulWidget {
  const CloudManagerPage({super.key});

  @override
  State<CloudManagerPage> createState() => _CloudManagerPageState();
}

class _FolderPathEntry {
  const _FolderPathEntry({required this.id, required this.name});

  final String id;
  final String name;
}

enum _FileAction { open, download }

class _CloudFilePayload {
  const _CloudFilePayload({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

class _HttpDownloadResult {
  const _HttpDownloadResult({
    required this.bytes,
    required this.headers,
  });

  final Uint8List bytes;
  final Map<String, String> headers;
}

class _CloudDownloadRequest {
  const _CloudDownloadRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.fileName,
    required this.accessToken,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String fileName;
  final String accessToken;
}

class _MediaStreamSource {
  const _MediaStreamSource({
    required this.uri,
    required this.fileName,
    required this.mimeType,
    this.headers = const <String, String>{},
  });

  final Uri uri;
  final String fileName;
  final String mimeType;
  final Map<String, String> headers;
}

class _TransferProgress {
  const _TransferProgress({
    required this.loadedBytes,
    required this.totalBytes,
    required this.fraction,
  });

  final int loadedBytes;
  final int? totalBytes;
  final double? fraction;
}

class _UploadProgressSnapshot {
  const _UploadProgressSnapshot({
    required this.fileName,
    required this.uploadedBytes,
    required this.totalBytes,
  });

  final String fileName;
  final int uploadedBytes;
  final int totalBytes;

  double get progressFraction {
    if (totalBytes <= 0) {
      return 0;
    }
    return (uploadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  int get progressPercent {
    if (totalBytes <= 0 || uploadedBytes <= 0) {
      return 0;
    }
    if (uploadedBytes >= totalBytes) {
      return 100;
    }
    final raw = progressFraction * 100;
    if (raw < 1) {
      return 1;
    }
    return raw.floor().clamp(1, 99);
  }
}

class _CloudManagerPageState extends State<CloudManagerPage>
    with WidgetsBindingObserver {
  static const int _largeFileStreamingThresholdBytes = 50 * 1024 * 1024;
  static const int _maxUploadAttempts = 4;
  static const int _oneDriveSimpleUploadLimitBytes = 4 * 1024 * 1024;
  static const int _oneDriveUploadChunkBytes = 5 * 1024 * 1024;
  static const int _dropboxSimpleUploadLimitBytes = 150 * 1024 * 1024;
  static const int _dropboxUploadChunkBytes = 8 * 1024 * 1024;
  static const Duration _uploadRequestTimeout = Duration(seconds: 120);
  static const Duration _authRequestTimeout = Duration(seconds: 25);
  static const int _uploadNotificationId = 9001;
  static const String _prefsAccountsKey = 'cloud_accounts_v1';
  static const String _prefsSelectedIndexKey = 'cloud_selected_index_v1';
  static const String _prefsDownloadDisclosureAcceptedKey =
      'download_disclosure_accepted_v1';
  static const String _openedTempDirName = 'moondrive_open_cache';
  static const String _downloadStagingDirName = 'moondrive_download_cache';
  static const Duration _openedTempTtl = Duration(minutes: 5);
  static const Duration _externalOpenCleanupDelay = Duration(seconds: 45);
  static const MethodChannel _androidStorageChannel = MethodChannel(
    'moondrive/android_storage',
  );

  late final CloudAuthService _authService = AppConfig.useRealAuth
      ? RealCloudAuthService()
      : FakeCloudAuthService();

  late List<CloudAccount> _accounts;
  int _selectedAccountIndex = 0;
  String _searchQuery = '';
  bool _isGridView = true;
  bool _isFolderLoading = false;
  bool _isUploading = false;
  _UploadProgressSnapshot? _uploadProgress;
  bool _isAppInForeground = true;
  bool? _isOnline;
  bool _showConnectivityBanner = false;
  Timer? _onlineBannerHideTimer;
  bool _isSyncingOnlineState = false;
  int _lastNotifiedUploadPercent = -1;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  int _notificationCounter = 1;
  bool _notificationsReady = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final Map<CloudProvider, List<_FolderPathEntry>> _folderPathByProvider =
      <CloudProvider, List<_FolderPathEntry>>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final isDemo = _authService is FakeCloudAuthService;
    _accounts = [
      CloudAccount(
        provider: CloudProvider.googleDrive,
        email: isDemo ? 'john.doe@gmail.com' : null,
        isConnected: isDemo,
        token: isDemo ? 'seed_google' : null,
        usedGb: isDemo ? 8.5 : 0,
        totalGb: 15,
        files: isDemo
            ? (FakeCloudAuthService()._filesFor(CloudProvider.googleDrive))
            : const [],
      ),
      const CloudAccount(
        provider: CloudProvider.oneDrive,
        usedGb: 0,
        totalGb: 5,
        files: [],
      ),
      const CloudAccount(
        provider: CloudProvider.dropbox,
        usedGb: 0,
        totalGb: 2,
        files: [],
      ),
    ];
    unawaited(_initializeNotifications());
    unawaited(_initializeConnectivityMonitoring());
    unawaited(_restorePersistedSession());
    unawaited(_purgeStaleOpenedTempFiles());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onlineBannerHideTimer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      final inForeground = state == AppLifecycleState.resumed;
      _isAppInForeground = inForeground;
      if (inForeground) {
        _runGuarded(_clearUploadProgressNotification());
        _runGuarded(_purgeStaleOpenedTempFiles(olderThan: const Duration(seconds: 45)));
        if (_isOnline == true) {
          _runGuarded(_syncSelectedAccountAfterReconnect());
        }
      } else if (_isUploading && _uploadProgress != null) {
        _runGuarded(_showUploadProgressNotification(_uploadProgress!));
      }
    } catch (e) {
      debugPrint('Lifecycle state handling failed: $e');
    }
  }

  void _runGuarded(Future<void> future) {
    unawaited(
      future.catchError((Object error, StackTrace stackTrace) {
        debugPrint('Async operation failed: $error');
      }),
    );
  }

  bool _hasNetworkConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<void> _initializeConnectivityMonitoring() async {
    final connectivity = Connectivity();

    try {
      final initialResults = await connectivity.checkConnectivity();
      if (!mounted) {
        return;
      }
      await _updateConnectivityState(initialResults, announce: false);
    } catch (e) {
      debugPrint('Initial connectivity check failed: $e');
      if (mounted) {
        setState(() {
          _isOnline = null;
          _isSyncingOnlineState = false;
        });
      }
    }

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(
      (results) {
        if (!mounted) {
          return;
        }
        _runGuarded(_updateConnectivityState(results));
      },
      onError: (Object error) {
        debugPrint('Connectivity listener failed: $error');
      },
    );
  }

  Future<void> _updateConnectivityState(
    List<ConnectivityResult> results, {
    bool announce = true,
  }) async {
    final isOnline = _hasNetworkConnection(results);
    final previousState = _isOnline;
    final isReconnect = previousState != true && isOnline;

    if (mounted) {
      setState(() {
        _isOnline = isOnline;
        _showConnectivityBanner = true;
      });
    } else {
      _isOnline = isOnline;
      _showConnectivityBanner = true;
    }

    if (!isOnline) {
      _onlineBannerHideTimer?.cancel();
      _onlineBannerHideTimer = null;
      return;
    }

    if (isReconnect) {
      _onlineBannerHideTimer?.cancel();
      _onlineBannerHideTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted || _isOnline != true) {
          return;
        }
        setState(() {
          _showConnectivityBanner = false;
        });
      });
    }

    if (isReconnect) {
      await _syncSelectedAccountAfterReconnect();
    }
  }

  Future<void> _syncSelectedAccountAfterReconnect() async {
    if (_isSyncingOnlineState || !_isAppInForeground || _isOnline != true) {
      return;
    }

    final selectedAccount = _accounts[_selectedAccountIndex];
    if (!selectedAccount.isConnected) {
      return;
    }

    final currentPath = List<_FolderPathEntry>.from(
      _folderPathByProvider[selectedAccount.provider] ?? const <_FolderPathEntry>[],
    );
    final currentFolderId = currentPath.isEmpty ? null : currentPath.last.id;

    if (mounted) {
      setState(() {
        _isSyncingOnlineState = true;
      });
    } else {
      _isSyncingOnlineState = true;
    }

    try {
      switch (selectedAccount.provider) {
        case CloudProvider.googleDrive:
          await _reloadGoogleDriveFolder(
            account: selectedAccount,
            folderId: currentFolderId,
            replacePath: currentPath,
          );
          break;
        case CloudProvider.oneDrive:
          await _reloadOneDriveFolder(
            account: selectedAccount,
            folderId: currentFolderId,
            replacePath: currentPath,
          );
          break;
        case CloudProvider.dropbox:
          await _reloadDropboxFolder(
            account: selectedAccount,
            folderPath: currentFolderId,
            replacePath: currentPath,
          );
          break;
      }
    } catch (e) {
      debugPrint('Reconnect sync failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingOnlineState = false;
        });
      } else {
        _isSyncingOnlineState = false;
      }
    }
  }

  Future<void> _initializeNotifications() async {
    if (!Platform.isAndroid) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    await _notificationsPlugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _notificationsReady = true;
  }

  Future<void> _handleNotificationTap(NotificationResponse response) async {
    final filePath = response.payload;
    if (filePath == null || filePath.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(filePath);
      if (decoded is Map<String, dynamic>) {
        final target = decoded['target']?.toString();
        final mime = decoded['mime']?.toString();
        if (target != null && target.isNotEmpty) {
          await _openDownloadedFile(target, mimeType: mime);
          return;
        }
      }
    } catch (_) {
      // Fall through to raw payload handling.
    }

    await _openDownloadedFile(filePath);
  }

  Future<void> _showDownloadCompletedNotification({
    required String fileTarget,
    required String fileName,
    required String mimeType,
  }) async {
    if (!_notificationsReady || !Platform.isAndroid) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'moondrive_downloads',
      'MoonDrive Downloads',
      channelDescription: 'Shows completed download notifications.',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _notificationsPlugin.show(
      _notificationCounter++,
      'Download complete',
      '$fileName saved in Downloads/MoonDrive Downloads. Tap to open.',
      const NotificationDetails(android: androidDetails),
      payload: jsonEncode(<String, String>{
        'target': fileTarget,
        'name': fileName,
        'mime': mimeType,
      }),
    );
  }

  Future<void> _openDownloadedFile(
    String fileTarget, {
    String? mimeType,
  }) async {
    if (fileTarget.startsWith('content://')) {
      try {
        final result = await _androidStorageChannel.invokeMethod<String>(
          'openUri',
          <String, dynamic>{
            'uri': fileTarget,
            'mimeType': mimeType ?? 'application/octet-stream',
          },
        );
        if (result != null && result.isNotEmpty && result != 'done') {
          _showActionNotice(result);
        }
        return;
      } catch (e) {
        _showActionNotice('Could not open downloaded file: $e');
        return;
      }
    }

    final result = await OpenFilex.open(fileTarget);
    if (result.type != ResultType.done) {
      _showActionNotice(
        result.message.isEmpty
            ? 'Could not open downloaded file.'
            : 'Could not open downloaded file: ${result.message}',
      );
    }
  }

  Future<void> _showUploadProgressNotification(
    _UploadProgressSnapshot progress,
  ) async {
    if (!_notificationsReady || !Platform.isAndroid || _isAppInForeground) {
      return;
    }

    if (_lastNotifiedUploadPercent == progress.progressPercent) {
      return;
    }
    _lastNotifiedUploadPercent = progress.progressPercent;

    final androidDetails = AndroidNotificationDetails(
      'moondrive_uploads',
      'MoonDrive Uploads',
      channelDescription: 'Shows background upload progress.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress.progressPercent,
    );

    try {
      await _notificationsPlugin.show(
        _uploadNotificationId,
        'Uploading ${progress.fileName}',
        '${_formatBytes(progress.uploadedBytes)} / ${_formatBytes(progress.totalBytes)} (${progress.progressPercent}%)',
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Upload progress notification failed: $e');
    }
  }

  Future<void> _clearUploadProgressNotification() async {
    if (!_notificationsReady || !Platform.isAndroid) {
      return;
    }
    _lastNotifiedUploadPercent = -1;
    try {
      await _notificationsPlugin.cancel(_uploadNotificationId);
    } catch (e) {
      debugPrint('Clearing upload notification failed: $e');
    }
  }

  void _updateUploadProgress({
    required String fileName,
    required int uploadedBytes,
    required int totalBytes,
  }) {
    final snapshot = _UploadProgressSnapshot(
      fileName: fileName,
      uploadedBytes: uploadedBytes,
      totalBytes: totalBytes,
    );
    if (mounted) {
      setState(() {
        _uploadProgress = snapshot;
      });
    } else {
      _uploadProgress = snapshot;
    }
    _runGuarded(_showUploadProgressNotification(snapshot));
  }

  @override
  Widget build(BuildContext context) {
    final selectedAccount = _accounts[_selectedAccountIndex];
    final accountFiles = selectedAccount.isConnected
        ? selectedAccount.files
        : const <DriveItem>[];
    final filteredItems = accountFiles
        .where(
          (item) => item.name.toLowerCase().contains(
            _searchQuery.toLowerCase().trim(),
          ),
        )
        .toList();
    final folderItems = filteredItems.where((item) => item.isFolder).toList();
    final fileItems = filteredItems.where((item) => !item.isFolder).toList();
    final currentPath =
        _folderPathByProvider[selectedAccount.provider] ??
        const <_FolderPathEntry>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactLayout = constraints.maxWidth < 980;

        final sidebar = _Sidebar(
          accounts: _accounts,
          selectedAccountIndex: _selectedAccountIndex,
          onSelect: (index) {
            setState(() {
              _selectedAccountIndex = index;
              _searchQuery = '';
            });
            unawaited(_persistSession());
            if (isCompactLayout) {
              Navigator.of(context).maybePop();
            }
          },
          onAddAccount: _showAddAccountDialog,
          onDisconnect: _disconnectAccount,
        );

        return PopScope(
          canPop: currentPath.isEmpty,
          onPopInvokedWithResult: (bool didPop, dynamic result) async {
            if (didPop) {
              return;
            }
            if (currentPath.isNotEmpty) {
              await _navigateUpFolder(selectedAccount);
            }
          },
          child: Scaffold(
            appBar: isCompactLayout
                ? AppBar(
                    title: const Text('Cloud File Manager'),
                    backgroundColor: const Color(0xFFF6F7FB),
                    elevation: 0,
                    scrolledUnderElevation: 0,
                  )
                : null,
            drawer: isCompactLayout
                ? Drawer(child: SafeArea(child: sidebar))
                : null,
            body: SafeArea(
              top: !isCompactLayout,
              child: isCompactLayout
                  ? _buildContentPane(
                      selectedAccount: selectedAccount,
                      folderItems: folderItems,
                      fileItems: fileItems,
                      currentPath: currentPath,
                      isCompactLayout: true,
                    )
                  : Row(
                      children: [
                        SizedBox(width: 260, child: sidebar),
                        Expanded(
                          child: _buildContentPane(
                            selectedAccount: selectedAccount,
                            folderItems: folderItems,
                            fileItems: fileItems,
                            currentPath: currentPath,
                            isCompactLayout: false,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContentPane({
    required CloudAccount selectedAccount,
    required List<DriveItem> folderItems,
    required List<DriveItem> fileItems,
    required List<_FolderPathEntry> currentPath,
    required bool isCompactLayout,
  }) {
    final mergedItems = <DriveItem>[...folderItems, ...fileItems];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompactLayout ? 14 : 20,
        isCompactLayout ? 12 : 20,
        isCompactLayout ? 14 : 20,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showConnectivityBanner && _isOnline != null) ...[
            _ConnectivityBanner(isOnline: _isOnline!),
            const SizedBox(height: 12),
          ],
          _Header(account: selectedAccount),
          if (selectedAccount.isConnected && currentPath.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _isFolderLoading
                      ? null
                      : () => _navigateUpFolder(selectedAccount),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back'),
                ),
                Text(
                  'My Files / ${currentPath.map((entry) => entry.name).join(' / ')}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _TopActions(
            key: ValueKey('actions_${selectedAccount.provider.name}'),
            isCompactLayout: isCompactLayout,
            isGridView: _isGridView,
            isUploading: _isUploading,
            onSearchChanged: (value) => setState(() => _searchQuery = value),
            onUpload: () => _uploadSelectedFile(selectedAccount),
            onCreateFolder: () => _createFolder(selectedAccount),
            onGridView: () => setState(() => _isGridView = true),
            onListView: () => setState(() => _isGridView = false),
          ),
          if (_isUploading) ...[
            const SizedBox(height: 10),
            _UploadProgressBanner(progress: _uploadProgress),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: selectedAccount.isConnected
                ? _isFolderLoading
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final crossAxisCount = isCompactLayout
                                ? (width > 320 ? 2 : 1)
                                : width > 1300
                                ? 6
                                : width > 980
                                ? 4
                                : width > 700
                                ? 3
                                : width > 460
                                ? 2
                                : 1;

                            if (mergedItems.isEmpty) {
                              return const _EmptyFilesState(
                                title: 'No files found',
                                subtitle: 'Try another search query.',
                              );
                            }

                            if (isCompactLayout) {
                              return ListView(
                                children: [
                                  _isGridView
                                      ? GridView.builder(
                                          itemCount: mergedItems.length,
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: crossAxisCount,
                                                crossAxisSpacing: 10,
                                                mainAxisSpacing: 10,
                                                childAspectRatio:
                                                    crossAxisCount == 1
                                                    ? 1.8
                                                    : 1.0,
                                              ),
                                          itemBuilder: (context, index) =>
                                              _ItemCard(
                                                item: mergedItems[index],
                                                isCompact: true,
                                                onTap: () => _onDriveItemTap(
                                                  mergedItems[index],
                                                  selectedAccount,
                                                ),
                                                onLongPress: () =>
                                                    _onDriveItemLongPress(
                                                      mergedItems[index],
                                                      selectedAccount,
                                                    ),
                                              ),
                                        )
                                      : Column(
                                          children: mergedItems
                                              .map(
                                                (item) => _ItemRow(
                                                  item: item,
                                                  onTap: () => _onDriveItemTap(
                                                    item,
                                                    selectedAccount,
                                                  ),
                                                  onLongPress: () =>
                                                      _onDriveItemLongPress(
                                                        item,
                                                        selectedAccount,
                                                      ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                ],
                              );
                            }

                            return ListView(
                              children: [
                                if (folderItems.isNotEmpty) ...[
                                  const _SectionTitle(title: 'Folders'),
                                  const SizedBox(height: 10),
                                  _isGridView
                                      ? GridView.builder(
                                          itemCount: folderItems.length,
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: crossAxisCount,
                                                crossAxisSpacing: 12,
                                                mainAxisSpacing: 12,
                                                childAspectRatio:
                                                    crossAxisCount == 1
                                                    ? 1.8
                                                    : 1.1,
                                              ),
                                          itemBuilder: (context, index) =>
                                              _ItemCard(
                                                item: folderItems[index],
                                                isCompact: isCompactLayout,
                                                onTap: () => _onDriveItemTap(
                                                  folderItems[index],
                                                  selectedAccount,
                                                ),
                                                onLongPress: () =>
                                                    _onDriveItemLongPress(
                                                      folderItems[index],
                                                      selectedAccount,
                                                    ),
                                              ),
                                        )
                                      : Column(
                                          children: folderItems
                                              .map(
                                                (item) => _ItemRow(
                                                  item: item,
                                                  onTap: () => _onDriveItemTap(
                                                    item,
                                                    selectedAccount,
                                                  ),
                                                  onLongPress: () =>
                                                      _onDriveItemLongPress(
                                                        item,
                                                        selectedAccount,
                                                      ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                  const SizedBox(height: 16),
                                ],
                                if (fileItems.isNotEmpty) ...[
                                  const _SectionTitle(title: 'Files'),
                                  const SizedBox(height: 10),
                                  _isGridView
                                      ? GridView.builder(
                                          itemCount: fileItems.length,
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: crossAxisCount,
                                                crossAxisSpacing: 12,
                                                mainAxisSpacing: 12,
                                                childAspectRatio:
                                                    crossAxisCount == 1
                                                    ? 1.8
                                                    : 1.1,
                                              ),
                                          itemBuilder: (context, index) =>
                                              _ItemCard(
                                                item: fileItems[index],
                                                isCompact: isCompactLayout,
                                                onTap: () => _onDriveItemTap(
                                                  fileItems[index],
                                                  selectedAccount,
                                                ),
                                                onLongPress: () =>
                                                    _onDriveItemLongPress(
                                                      fileItems[index],
                                                      selectedAccount,
                                                    ),
                                              ),
                                        )
                                      : Column(
                                          children: fileItems
                                              .map(
                                                (item) => _ItemRow(
                                                  item: item,
                                                  onTap: () => _onDriveItemTap(
                                                    item,
                                                    selectedAccount,
                                                  ),
                                                  onLongPress: () =>
                                                      _onDriveItemLongPress(
                                                        item,
                                                        selectedAccount,
                                                      ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                ],
                              ],
                            );
                          },
                        )
                : _DisconnectedState(
                    providerLabel: selectedAccount.name,
                    error: selectedAccount.lastError,
                  ),
          ),
          if (!isCompactLayout) ...[
            const SizedBox(height: 10),
            const _FeedbackBar(),
          ],
        ],
      ),
    );
  }

  void _showActionNotice(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  CloudAccount _accountByProvider(CloudProvider provider) {
    return _accounts.firstWhere((item) => item.provider == provider);
  }

  bool _isTokenExpiredOrNearExpiry(CloudAccount account) {
    final expiry = account.tokenExpiryEpochMs;
    if (expiry == null) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= (expiry - const Duration(minutes: 2).inMilliseconds);
  }

  bool _isTokenUnauthorizedError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('http 401') ||
        text.contains('unauthorized') ||
        text.contains('invalid_access_token') ||
        text.contains('token expired') ||
        text.contains('access token has expired');
  }

  bool _isTransientUploadError(Object error) {
    if (_isUploadTimeoutError(error)) {
      return true;
    }
    final text = error.toString().toLowerCase();
    return text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('software caused connection abort') ||
        text.contains('broken pipe') ||
        text.contains('request cancelled') ||
        text.contains('request canceled') ||
        text.contains('socketexception') ||
        text.contains('network is unreachable') ||
        text.contains('timed out');
  }

  Future<void> _waitForForegroundBeforeRetry({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (_isAppInForeground) {
      return;
    }
    final start = DateTime.now();
    while (!_isAppInForeground && DateTime.now().difference(start) < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<CloudAccount> _ensureActiveAccessToken(
    CloudAccount account, {
    bool forceRefresh = false,
  }) async {
    final latest = _accountByProvider(account.provider);
    final token = latest.token;
    final hasToken = token != null && token.isNotEmpty;
    final shouldBootstrapExpiry =
        latest.provider != CloudProvider.googleDrive &&
        (latest.refreshToken?.isNotEmpty ?? false) &&
        latest.tokenExpiryEpochMs == null;
    final shouldRefresh =
        forceRefresh ||
        !hasToken ||
        _isTokenExpiredOrNearExpiry(latest) ||
        shouldBootstrapExpiry;

    if (!shouldRefresh) {
      return latest;
    }

    try {
      switch (latest.provider) {
        case CloudProvider.googleDrive:
          return _refreshGoogleDriveAccessToken(latest);
        case CloudProvider.oneDrive:
          return _refreshOneDriveAccessToken(latest);
        case CloudProvider.dropbox:
          return _refreshDropboxAccessToken(latest);
      }
    } catch (_) {
      if (!forceRefresh && hasToken) {
        return latest;
      }
      rethrow;
    }
  }

  Future<CloudAccount> _refreshGoogleDriveAccessToken(CloudAccount account) async {
    final signIn = GoogleSignIn(
      scopes: const <String>['email', drive.DriveApi.driveFileScope],
      serverClientId: AppConfig.googleServerClientId.isEmpty
          ? null
          : AppConfig.googleServerClientId,
    );

    final signedIn = await signIn.signInSilently();
    if (signedIn == null) {
      throw CloudAuthException(
        'Google session expired. Please login again.',
      );
    }

    final auth = await signedIn.authentication;
    final accessToken = auth.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw CloudAuthException('Google access token refresh failed.');
    }

    final refreshed = account.copyWith(
      token: accessToken,
      tokenExpiryEpochMs:
          DateTime.now().millisecondsSinceEpoch +
          const Duration(minutes: 50).inMilliseconds,
      clearError: true,
    );

    if (mounted) {
      setState(() => _replaceAccount(account.provider, refreshed));
    } else {
      _replaceAccount(account.provider, refreshed);
    }
    unawaited(_persistSession());
    return refreshed;
  }

  Future<CloudAccount> _refreshOneDriveAccessToken(CloudAccount account) async {
    final refreshToken = account.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw CloudAuthException(
        'OneDrive session expired. Please login again once.',
      );
    }

    final response = await http.post(
      Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: <String, String>{
        'client_id': AppConfig.oneDriveClientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'redirect_uri': AppConfig.oneDriveRedirectUri,
      },
    ).timeout(_authRequestTimeout);

    final payload = _decodeAnyMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudAuthException(
        'OneDrive token refresh failed (${response.statusCode}). Please login again.',
      );
    }

    final accessToken = (payload['access_token'] as String?) ?? '';
    if (accessToken.isEmpty) {
      throw CloudAuthException('OneDrive refresh did not return an access token.');
    }

    final newRefreshToken =
        (payload['refresh_token'] as String?)?.trim().isNotEmpty == true
        ? (payload['refresh_token'] as String).trim()
        : refreshToken;
    final expiresInSeconds = _toInt(payload['expires_in']);
    final refreshed = account.copyWith(
      token: accessToken,
      refreshToken: newRefreshToken,
      tokenExpiryEpochMs:
          DateTime.now().millisecondsSinceEpoch +
          ((expiresInSeconds > 0 ? expiresInSeconds : 3600) * 1000) -
          const Duration(minutes: 2).inMilliseconds,
      clearError: true,
    );

    if (mounted) {
      setState(() => _replaceAccount(account.provider, refreshed));
    } else {
      _replaceAccount(account.provider, refreshed);
    }
    unawaited(_persistSession());
    return refreshed;
  }

  Future<CloudAccount> _refreshDropboxAccessToken(CloudAccount account) async {
    final refreshToken = account.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw CloudAuthException(
        'Dropbox session expired. Please login again once.',
      );
    }

    final response = await http.post(
      Uri.https('api.dropboxapi.com', '/oauth2/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: <String, String>{
        'client_id': AppConfig.dropboxClientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    ).timeout(_authRequestTimeout);

    final payload = _decodeAnyMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudAuthException(
        'Dropbox token refresh failed (${response.statusCode}). Please login again.',
      );
    }

    final accessToken = (payload['access_token'] as String?) ?? '';
    if (accessToken.isEmpty) {
      throw CloudAuthException('Dropbox refresh did not return an access token.');
    }

    final expiresInSeconds = _toInt(payload['expires_in']);
    final refreshed = account.copyWith(
      token: accessToken,
      refreshToken: refreshToken,
      tokenExpiryEpochMs:
          DateTime.now().millisecondsSinceEpoch +
          ((expiresInSeconds > 0 ? expiresInSeconds : 3600) * 1000) -
          const Duration(minutes: 2).inMilliseconds,
      clearError: true,
    );

    if (mounted) {
      setState(() => _replaceAccount(account.provider, refreshed));
    } else {
      _replaceAccount(account.provider, refreshed);
    }
    unawaited(_persistSession());
    return refreshed;
  }

  Future<void> _uploadSelectedFile(CloudAccount account) async {
    if (_isUploading) {
      _showActionNotice('An upload is already in progress.');
      return;
    }

    if (!account.isConnected) {
      _showActionNotice('Please login to ${account.name} before uploading.');
      return;
    }

    final pickResult = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.any,
    );

    if (pickResult == null || pickResult.files.isEmpty) {
      _showActionNotice('File selection canceled.');
      return;
    }

    final uploadItems = <({File sourceFile, String fileName, int sizeBytes})>[];
    for (final selectedFile in pickResult.files) {
      final selectedPath = selectedFile.path;
      if (selectedPath == null || selectedPath.trim().isEmpty) {
        continue;
      }

      final sourceFile = File(selectedPath);
      if (!await sourceFile.exists()) {
        continue;
      }

      final fileSizeBytes =
          selectedFile.size > 0 ? selectedFile.size : await sourceFile.length();

      final fallbackName = _basenameFromPath(selectedFile.path);
      final fileName = selectedFile.name.trim().isNotEmpty
          ? selectedFile.name.trim()
          : (fallbackName ?? 'upload_${DateTime.now().millisecondsSinceEpoch}');

      uploadItems.add((
        sourceFile: sourceFile,
        fileName: fileName,
        sizeBytes: fileSizeBytes,
      ));
    }

    if (uploadItems.isEmpty) {
      _showActionNotice('Could not access the selected file(s).');
      return;
    }

    final totalSizeBytes = uploadItems.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );

    final shouldUpload = await _confirmUpload(
      accountName: account.name,
      fileName: uploadItems.length == 1
          ? uploadItems.first.fileName
          : '${uploadItems.length} files',
      sizeBytes: totalSizeBytes,
      fileCount: uploadItems.length,
      fileNames: uploadItems.map((item) => item.fileName).toList(growable: false),
    );
    if (!shouldUpload) {
      _showActionNotice('Upload canceled.');
      return;
    }

    final currentPath =
        _folderPathByProvider[account.provider] ?? const <_FolderPathEntry>[];
    final parentFolderId = currentPath.isEmpty ? null : currentPath.last.id;

    setState(() {
      _isUploading = true;
      _uploadProgress = _UploadProgressSnapshot(
        fileName: uploadItems.length == 1
            ? uploadItems.first.fileName
            : 'Preparing ${uploadItems.length} files',
        uploadedBytes: 0,
        totalBytes: totalSizeBytes,
      );
    });
    _lastNotifiedUploadPercent = -1;
    try {
      var authAccount = await _ensureActiveAccessToken(account);
      Object? lastUploadError;
      var uploadedCount = 0;

      for (final item in uploadItems) {
        for (var attempt = 0; attempt < _maxUploadAttempts; attempt++) {
          try {
            final token = authAccount.token;
            if (token == null || token.isEmpty) {
              throw CloudAuthException(
                'Your ${account.name} session expired. Please login again.',
              );
            }

            _updateUploadProgress(
              fileName: item.fileName,
              uploadedBytes: 0,
              totalBytes: item.sizeBytes,
            );

            await _performProviderUpload(
              provider: account.provider,
              accessToken: token,
              fileName: item.fileName,
              sourceFile: item.sourceFile,
              parentFolderId: parentFolderId,
              onProgress: (uploadedBytes, totalBytes) {
                _updateUploadProgress(
                  fileName: item.fileName,
                  uploadedBytes: uploadedBytes,
                  totalBytes: totalBytes,
                );
              },
            );

            uploadedCount++;
            await _reloadCurrentProviderFolderAfterUpload(
              account: authAccount,
              parentFolderId: parentFolderId,
              currentPath: currentPath,
            );

            lastUploadError = null;
            break;
          } catch (e) {
            lastUploadError = e;
            final isUnauthorized = _isTokenUnauthorizedError(e);
            final isTransient = _isTransientUploadError(e);
            if (attempt < _maxUploadAttempts - 1 &&
                (isUnauthorized || isTransient)) {
              if (isUnauthorized) {
                authAccount = await _ensureActiveAccessToken(
                  authAccount,
                  forceRefresh: true,
                );
              }
              if (!_isAppInForeground) {
                await _waitForForegroundBeforeRetry();
              }
              await Future<void>.delayed(
                Duration(milliseconds: 350 * (attempt + 1)),
              );
              _updateUploadProgress(
                fileName: item.fileName,
                uploadedBytes: 0,
                totalBytes: item.sizeBytes,
              );
              continue;
            }
            rethrow;
          }
        }
      }

      if (lastUploadError != null) {
        throw lastUploadError;
      }

      _showActionNotice(
        uploadedCount == 1
            ? 'Uploaded "${uploadItems.first.fileName}" to ${account.name}. '
            : 'Uploaded $uploadedCount files to ${account.name}.',
      );
    } catch (e) {
      final message = e.toString();
      if (message.contains('insufficientPermissions') ||
          message.contains('insufficientFilePermissions') ||
          message.contains('access_denied') ||
          message.contains('not_authorized')) {
        _showActionNotice(
          'Upload permission missing. Please logout/login to refresh ${account.name} permissions.',
        );
        return;
      }
      _showActionNotice('Upload failed: $e');
    } finally {
      await _clearUploadProgressNotification();
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = null;
        });
      } else {
        _isUploading = false;
        _uploadProgress = null;
      }
    }
  }

  Future<void> _createFolder(CloudAccount account) async {
    if (_isUploading || _isFolderLoading) {
      _showActionNotice('Please wait for the current operation to finish.');
      return;
    }
    if (!account.isConnected) {
      _showActionNotice('Please login to ${account.name} before creating folders.');
      return;
    }

    final folderName = await _promptCreateFolderName();
    if (folderName == null) {
      return;
    }

    final currentPath =
        _folderPathByProvider[account.provider] ?? const <_FolderPathEntry>[];
    final parentFolderId = currentPath.isEmpty ? null : currentPath.last.id;

    setState(() => _isFolderLoading = true);
    try {
      var authAccount = await _ensureActiveAccessToken(account);
      Object? lastError;

      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final token = authAccount.token;
          if (token == null || token.isEmpty) {
            throw CloudAuthException(
              'Your ${account.name} session expired. Please login again.',
            );
          }

          await _performCreateFolder(
            provider: account.provider,
            accessToken: token,
            folderName: folderName,
            parentFolderId: parentFolderId,
          );

          await _reloadCurrentProviderFolderAfterUpload(
            account: authAccount,
            parentFolderId: parentFolderId,
            currentPath: List<_FolderPathEntry>.from(currentPath),
          );

          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          final isUnauthorized = _isTokenUnauthorizedError(e);
          final isTransient = _isTransientUploadError(e);
          if (attempt == 0 && (isUnauthorized || isTransient)) {
            if (isUnauthorized) {
              authAccount = await _ensureActiveAccessToken(
                authAccount,
                forceRefresh: true,
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 300));
            continue;
          }
          rethrow;
        }
      }

      if (lastError != null) {
        throw lastError;
      }

      _showActionNotice('Folder "$folderName" created in ${account.name}.');
    } catch (e) {
      _showActionNotice('Folder creation failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isFolderLoading = false);
      } else {
        _isFolderLoading = false;
      }
    }
  }

  Future<String?> _promptCreateFolderName() async {
    final controller = TextEditingController();
    String? validationError;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Create folder'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Folder name',
                        hintText: 'New folder',
                      ),
                      onSubmitted: (_) {
                        final trimmed = controller.text.trim();
                        if (trimmed.isEmpty) {
                          setLocalState(
                            () => validationError = 'Folder name is required.',
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop(trimmed);
                      },
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final trimmed = controller.text.trim();
                    if (trimmed.isEmpty) {
                      setLocalState(
                        () => validationError = 'Folder name is required.',
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(trimmed);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    return result?.trim().isEmpty ?? true ? null : result!.trim();
  }

  Future<void> _performCreateFolder({
    required CloudProvider provider,
    required String accessToken,
    required String folderName,
    required String? parentFolderId,
  }) {
    switch (provider) {
      case CloudProvider.googleDrive:
        return _createGoogleDriveFolder(
          accessToken: accessToken,
          folderName: folderName,
          parentFolderId: parentFolderId,
        );
      case CloudProvider.oneDrive:
        return _createOneDriveFolder(
          accessToken: accessToken,
          folderName: folderName,
          parentFolderId: parentFolderId,
        );
      case CloudProvider.dropbox:
        return _createDropboxFolder(
          accessToken: accessToken,
          folderName: folderName,
          parentFolderPath: parentFolderId,
        );
    }
  }

  Future<void> _createGoogleDriveFolder({
    required String accessToken,
    required String folderName,
    required String? parentFolderId,
  }) async {
    final client = _AccessTokenClient(accessToken);
    try {
      final api = drive.DriveApi(client);
      final metadata = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents =
            parentFolderId == null ? null : <String>[parentFolderId];
      await api.files.create(metadata, $fields: 'id,name');
    } finally {
      client.close();
    }
  }

  Future<void> _createOneDriveFolder({
    required String accessToken,
    required String folderName,
    required String? parentFolderId,
  }) async {
    final client = _AccessTokenClient(accessToken);
    try {
      final endpoint = parentFolderId == null
          ? '/v1.0/me/drive/root/children'
          : '/v1.0/me/drive/items/${Uri.encodeComponent(parentFolderId)}/children';
      final response = await client.post(
        Uri.https('graph.microsoft.com', endpoint),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'name': folderName,
          'folder': <String, dynamic>{},
          '@microsoft.graph.conflictBehavior': 'rename',
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudAuthException(
          'OneDrive folder creation failed (HTTP ${response.statusCode}).',
        );
      }
    } finally {
      client.close();
    }
  }

  Future<void> _createDropboxFolder({
    required String accessToken,
    required String folderName,
    required String? parentFolderPath,
  }) async {
    final client = _AccessTokenClient(accessToken);
    try {
      final normalizedParent = (parentFolderPath == null ||
              parentFolderPath.isEmpty ||
              parentFolderPath == '/')
          ? ''
          : parentFolderPath;
      final targetPath = normalizedParent.isEmpty
          ? '/$folderName'
          : '$normalizedParent/$folderName';

      final response = await client.post(
        Uri.https('api.dropboxapi.com', '/2/files/create_folder_v2'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'path': targetPath,
          'autorename': true,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudAuthException(
          'Dropbox folder creation failed (HTTP ${response.statusCode}).',
        );
      }
    } finally {
      client.close();
    }
  }

  Future<void> _performProviderUpload({
    required CloudProvider provider,
    required String accessToken,
    required String fileName,
    required File sourceFile,
    required String? parentFolderId,
    required void Function(int uploadedBytes, int totalBytes) onProgress,
  }) {
    switch (provider) {
      case CloudProvider.googleDrive:
        return _uploadGoogleDriveFile(
          accessToken: accessToken,
          fileName: fileName,
          sourceFile: sourceFile,
          parentFolderId: parentFolderId,
          onProgress: onProgress,
        );
      case CloudProvider.oneDrive:
        return _uploadOneDriveFile(
          accessToken: accessToken,
          fileName: fileName,
          sourceFile: sourceFile,
          parentFolderId: parentFolderId,
          onProgress: onProgress,
        );
      case CloudProvider.dropbox:
        return _uploadDropboxFile(
          accessToken: accessToken,
          fileName: fileName,
          sourceFile: sourceFile,
          parentFolderPath: parentFolderId,
          onProgress: onProgress,
        );
    }
  }

  Future<void> _reloadCurrentProviderFolderAfterUpload({
    required CloudAccount account,
    required String? parentFolderId,
    required List<_FolderPathEntry> currentPath,
  }) {
    switch (account.provider) {
      case CloudProvider.googleDrive:
        return _reloadGoogleDriveFolder(
          account: account,
          folderId: parentFolderId,
          replacePath: List<_FolderPathEntry>.from(currentPath),
        );
      case CloudProvider.oneDrive:
        return _reloadOneDriveFolder(
          account: account,
          folderId: parentFolderId,
          replacePath: List<_FolderPathEntry>.from(currentPath),
        );
      case CloudProvider.dropbox:
        return _reloadDropboxFolder(
          account: account,
          folderPath: parentFolderId,
          replacePath: List<_FolderPathEntry>.from(currentPath),
        );
    }
  }

  Future<void> _uploadGoogleDriveFile({
    required String accessToken,
    required String fileName,
    required File sourceFile,
    required String? parentFolderId,
    required void Function(int uploadedBytes, int totalBytes) onProgress,
  }) async {
    final client = _AccessTokenClient(accessToken);
    try {
      final api = drive.DriveApi(client);
      final metadata = drive.File()
        ..name = fileName
        ..parents =
            parentFolderId == null ? null : <String>[parentFolderId];

      final length = await sourceFile.length();
      onProgress(0, length);
      final media = drive.Media(
        _trackUploadStream(
          sourceFile: sourceFile,
          totalBytes: length,
          onProgress: onProgress,
        ),
        length,
      );
      await api.files.create(
        metadata,
        uploadMedia: media,
        $fields: 'id,name',
      );
    } finally {
      client.close();
    }
  }

  Stream<List<int>> _trackUploadStream({
    required File sourceFile,
    required int totalBytes,
    required void Function(int uploadedBytes, int totalBytes) onProgress,
  }) {
    var uploaded = 0;
    return sourceFile.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          uploaded += chunk.length;
          if (uploaded > totalBytes) {
            uploaded = totalBytes;
          }
          onProgress(uploaded, totalBytes);
          sink.add(chunk);
        },
      ),
    );
  }

  Future<http.Response> _sendChunkRequestWithProgress({
    required http.Client client,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List chunk,
    required int alreadyUploaded,
    required int totalBytes,
    required void Function(int uploadedBytes, int totalBytes) onProgress,
  }) async {
    final request = http.StreamedRequest(method, uri)
      ..headers.addAll(headers)
      ..contentLength = chunk.length;

    final responseFuture = client.send(request).timeout(_uploadRequestTimeout);

    const writeStepBytes = 64 * 1024;
    var sentBytes = 0;
    while (sentBytes < chunk.length) {
      final end = min(sentBytes + writeStepBytes, chunk.length);
      request.sink.add(chunk.sublist(sentBytes, end));
      sentBytes = end;
      onProgress(min(alreadyUploaded + sentBytes, totalBytes), totalBytes);
      await Future<void>.delayed(Duration.zero);
    }

    await request.sink.close();
    final streamed = await responseFuture;
    return http.Response.fromStream(streamed).timeout(_uploadRequestTimeout);
  }

  Future<void> _uploadOneDriveFile({
    required String accessToken,
    required String fileName,
    required File sourceFile,
    required String? parentFolderId,
    required void Function(int uploadedBytes, int totalBytes) onProgress,
  }) async {
    final client = _AccessTokenClient(accessToken);
    try {
      final length = await sourceFile.length();
      onProgress(0, length);
      if (length <= _oneDriveSimpleUploadLimitBytes) {
        final encodedName = Uri.encodeComponent(fileName);
        final encodedParent = parentFolderId == null
            ? null
            : Uri.encodeComponent(parentFolderId);
        final uri = parentFolderId == null
            ? Uri.parse(
                'https://graph.microsoft.com/v1.0/me/drive/root:/$encodedName:/content',
              )
            : Uri.parse(
                'https://graph.microsoft.com/v1.0/me/drive/items/$encodedParent:/$encodedName:/content',
              );

        final request = http.StreamedRequest('PUT', uri)
          ..headers['Content-Type'] = 'application/octet-stream'
          ..contentLength = length;

        final responseFuture = client.send(request).timeout(_uploadRequestTimeout);

        await request.sink.addStream(
          _trackUploadStream(
            sourceFile: sourceFile,
            totalBytes: length,
            onProgress: onProgress,
          ),
        );
        await request.sink.close();

        final streamed = await responseFuture;
        final response = await http.Response.fromStream(streamed).timeout(
          _uploadRequestTimeout,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw CloudAuthException(
            'OneDrive upload failed (HTTP ${response.statusCode}): ${_compactErrorBody(response.body)}',
          );
        }
        onProgress(length, length);
        return;
      }

      await _uploadOneDriveLargeFile(
        client: client,
        fileName: fileName,
        sourceFile: sourceFile,
        parentFolderId: parentFolderId,
        totalBytes: length,
        onProgress: onProgress,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _uploadDropboxFile({
    required String accessToken,
    required String fileName,
    required File sourceFile,
    required String? parentFolderPath,
    required void Function(int uploadedBytes, int totalBytes) onProgress,
  }) async {
    final client = _AccessTokenClient(accessToken);
    try {
      final normalizedFolder = (parentFolderPath == null ||
              parentFolderPath.isEmpty ||
              parentFolderPath == '/')
          ? ''
          : parentFolderPath;
      final destinationPath = normalizedFolder.isEmpty
          ? '/$fileName'
          : '$normalizedFolder/$fileName';

      final totalBytes = await sourceFile.length();
      onProgress(0, totalBytes);
      if (totalBytes <= _dropboxSimpleUploadLimitBytes) {
        final request = http.StreamedRequest(
          'POST',
          Uri.https('content.dropboxapi.com', '/2/files/upload'),
        )
          ..headers['Content-Type'] = 'application/octet-stream'
          ..headers['Dropbox-API-Arg'] = jsonEncode(<String, dynamic>{
            'path': destinationPath,
            'mode': 'add',
            'autorename': true,
            'mute': false,
          })
          ..contentLength = totalBytes;

        final responseFuture = client.send(request).timeout(_uploadRequestTimeout);

        await request.sink.addStream(
          _trackUploadStream(
            sourceFile: sourceFile,
            totalBytes: totalBytes,
            onProgress: onProgress,
          ),
        );
        await request.sink.close();

        final streamed = await responseFuture;
        final response = await http.Response.fromStream(streamed).timeout(
          _uploadRequestTimeout,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw CloudAuthException(
            'Dropbox upload failed (HTTP ${response.statusCode}): ${_compactErrorBody(response.body)}',
          );
        }
        onProgress(totalBytes, totalBytes);
        return;
      }

      await _uploadDropboxLargeFile(
        client: client,
        sourceFile: sourceFile,
        destinationPath: destinationPath,
        totalBytes: totalBytes,
        onProgress: onProgress,
      );
    } finally {
      client.close();
    }
  }


  Future<void> _uploadOneDriveLargeFile({
    required _AccessTokenClient client,
    required String fileName,
    required File sourceFile,
    required String? parentFolderId,
    required int totalBytes,
    required void Function(int uploadedBytes, int totalBytes) onProgress,
  }) async {
    final encodedName = Uri.encodeComponent(fileName);
    final encodedParent = parentFolderId == null
        ? null
        : Uri.encodeComponent(parentFolderId);
    final sessionEndpoint = parentFolderId == null
        ? '/v1.0/me/drive/root:/$encodedName:/createUploadSession'
        : '/v1.0/me/drive/items/$encodedParent:/$encodedName:/createUploadSession';

    final sessionResponse = await client
        .post(
          Uri.https('graph.microsoft.com', sessionEndpoint),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'item': <String, dynamic>{
              '@microsoft.graph.conflictBehavior': 'replace',
              'name': fileName,
            },
          }),
        )
        .timeout(_uploadRequestTimeout);

    if (sessionResponse.statusCode < 200 || sessionResponse.statusCode >= 300) {
      throw CloudAuthException(
        'OneDrive upload session failed (HTTP ${sessionResponse.statusCode}): ${_compactErrorBody(sessionResponse.body)}',
      );
    }

    final payload = _decodeAnyMap(sessionResponse.body);
    final uploadUrl = payload['uploadUrl'] as String?;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw CloudAuthException('OneDrive upload URL was not returned.');
    }

    final uploadClient = http.Client();
    final raf = await sourceFile.open();
    var offset = 0;
    try {
      while (offset < totalBytes) {
        final chunkSize = min(_oneDriveUploadChunkBytes, totalBytes - offset);
        await raf.setPosition(offset);
        final chunk = await raf.read(chunkSize);
        if (chunk.isEmpty) {
          throw CloudAuthException('OneDrive upload stopped unexpectedly.');
        }

        final response = await _sendChunkRequestWithProgress(
          client: uploadClient,
          method: 'PUT',
          uri: Uri.parse(uploadUrl),
          headers: <String, String>{
            'Content-Length': '${chunk.length}',
            'Content-Range':
                'bytes $offset-${offset + chunk.length - 1}/$totalBytes',
            'Content-Type': 'application/octet-stream',
          },
          chunk: chunk,
          alreadyUploaded: offset,
          totalBytes: totalBytes,
          onProgress: onProgress,
        );

        if (response.statusCode != 200 &&
            response.statusCode != 201 &&
            response.statusCode != 202) {
          throw CloudAuthException(
            'OneDrive chunk upload failed (HTTP ${response.statusCode}): ${_compactErrorBody(response.body)}',
          );
        }

        offset += chunk.length;
        onProgress(offset, totalBytes);
      }
      onProgress(totalBytes, totalBytes);
    } finally {
      await raf.close();
      uploadClient.close();
    }
  }

  Future<void> _uploadDropboxLargeFile({
    required _AccessTokenClient client,
    required File sourceFile,
    required String destinationPath,
    required int totalBytes,
    required void Function(int uploadedBytes, int totalBytes) onProgress,
  }) async {
    final raf = await sourceFile.open();
    var offset = 0;
    try {
      final firstChunk = await raf.read(min(_dropboxUploadChunkBytes, totalBytes));
      final startResponse = await _sendChunkRequestWithProgress(
        client: client,
        method: 'POST',
        uri: Uri.https('content.dropboxapi.com', '/2/files/upload_session/start'),
        headers: <String, String>{
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode(
            const <String, dynamic>{'close': false},
          ),
        },
        chunk: firstChunk,
        alreadyUploaded: offset,
        totalBytes: totalBytes,
        onProgress: onProgress,
      );
      if (startResponse.statusCode < 200 || startResponse.statusCode >= 300) {
        throw CloudAuthException(
          'Dropbox upload session start failed (HTTP ${startResponse.statusCode}): ${_compactErrorBody(startResponse.body)}',
        );
      }

      final startPayload = _decodeAnyMap(startResponse.body);
      final sessionId = startPayload['session_id'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        throw CloudAuthException('Dropbox upload session id missing.');
      }

      offset += firstChunk.length;
      onProgress(offset, totalBytes);

      while (offset < totalBytes) {
        final remaining = totalBytes - offset;
        final chunkSize = min(_dropboxUploadChunkBytes, remaining);
        await raf.setPosition(offset);
        final chunk = await raf.read(chunkSize);
        if (chunk.isEmpty) {
          break;
        }

        final isLast = (offset + chunk.length) >= totalBytes;
        final endpoint = isLast
            ? '/2/files/upload_session/finish'
            : '/2/files/upload_session/append_v2';
        final arg = isLast
            ? <String, dynamic>{
                'cursor': <String, dynamic>{
                  'session_id': sessionId,
                  'offset': offset,
                },
                'commit': <String, dynamic>{
                  'path': destinationPath,
                  'mode': 'add',
                  'autorename': true,
                  'mute': false,
                },
              }
            : <String, dynamic>{
                'cursor': <String, dynamic>{
                  'session_id': sessionId,
                  'offset': offset,
                },
                'close': false,
              };

        final response = await _sendChunkRequestWithProgress(
          client: client,
          method: 'POST',
          uri: Uri.https('content.dropboxapi.com', endpoint),
          headers: <String, String>{
            'Content-Type': 'application/octet-stream',
            'Dropbox-API-Arg': jsonEncode(arg),
          },
          chunk: chunk,
          alreadyUploaded: offset,
          totalBytes: totalBytes,
          onProgress: onProgress,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw CloudAuthException(
            'Dropbox chunk upload failed (HTTP ${response.statusCode}): ${_compactErrorBody(response.body)}',
          );
        }

        offset += chunk.length;
        onProgress(offset, totalBytes);
      }
      onProgress(totalBytes, totalBytes);
    } finally {
      await raf.close();
    }
  }

  Future<Directory> _resolveOpenedTempDirectory() async {
    final rootTemp = await getTemporaryDirectory();
    final cacheDir = Directory(
      '${rootTemp.path}${Platform.pathSeparator}$_openedTempDirName',
    );
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<File> _writeOpenedTempFile({
    required String preferredName,
    required List<int> bytes,
  }) async {
    final cacheDir = await _resolveOpenedTempDirectory();
    final safeName = _sanitizeFileName(preferredName);
    final baseName = safeName.isEmpty
        ? 'file_${DateTime.now().millisecondsSinceEpoch}'
        : safeName;
    final file = File(
      '${cacheDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_$baseName',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void _scheduleOpenedTempFileCleanup(
    File file, {
    Duration delay = _externalOpenCleanupDelay,
  }) {
    unawaited(
      Future<void>.delayed(delay, () async {
        await _deleteFileQuietly(file);
      }),
    );
  }

  Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // External viewers may still hold a file lock.
    }
  }

  Future<void> _purgeStaleOpenedTempFiles({
    Duration olderThan = _openedTempTtl,
  }) async {
    try {
      final cacheDir = await _resolveOpenedTempDirectory();
      final threshold = DateTime.now().subtract(olderThan);
      await for (final entity in cacheDir.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(threshold)) {
            await entity.delete();
          }
        } catch (_) {
          // Ignore per-file cleanup failures.
        }
      }
    } catch (e) {
      debugPrint('Temp cleanup failed: $e');
    }
  }

  String _compactErrorBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return 'no error body';
    }
    return trimmed.length > 220 ? '${trimmed.substring(0, 220)}...' : trimmed;
  }

  bool _isUploadTimeoutError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('timeoutexception') ||
        text.contains('timed out') ||
        text.contains('deadline exceeded');
  }

  DriveItem _mapOneDriveListItem(Map<String, dynamic> item) {
    final isFolder = item['folder'] != null;
    final modified = DateTime.tryParse(
      (item['lastModifiedDateTime'] as String?) ?? '',
    );
    final size = _toInt(item['size']);
    final fileMeta = (item['file'] as Map?)?.cast<String, dynamic>();
    final mimeType = isFolder
        ? 'application/vnd.google-apps.folder'
        : ((fileMeta?['mimeType'] as String?) ??
              _guessMimeTypeByName((item['name'] as String?) ?? ''));

    return DriveItem(
      id: item['id'] as String?,
      name: (item['name'] as String?) ?? 'Untitled',
      subtitle: isFolder ? 'Folder' : _formatBytes(size),
      trailingInfo: _formatModifiedDate(modified),
      icon: _iconForMimeType(mimeType, isFolder: isFolder),
      iconColor: _colorForMimeType(mimeType, isFolder: isFolder),
      mimeType: mimeType,
      sizeBytes: isFolder ? null : size,
      webViewLink: item['webUrl'] as String?,
      webContentLink: item['webUrl'] as String?,
    );
  }

  DriveItem _mapDropboxListItem(Map<String, dynamic> item) {
    final tag = item['.tag'] as String?;
    final isFolder = tag == 'folder';
    final modified = DateTime.tryParse((item['server_modified'] as String?) ?? '');
    final size = _toInt(item['size']);
    final name = (item['name'] as String?) ?? 'Untitled';
    final mimeType = isFolder
        ? 'application/vnd.google-apps.folder'
        : _guessMimeTypeByName(name);

    return DriveItem(
      id: (item['path_lower'] as String?) ?? (item['id'] as String?),
      name: name,
      subtitle: isFolder ? 'Folder' : _formatBytes(size),
      trailingInfo: _formatModifiedDate(modified),
      icon: _iconForMimeType(mimeType, isFolder: isFolder),
      iconColor: _colorForMimeType(mimeType, isFolder: isFolder),
      mimeType: mimeType,
      sizeBytes: isFolder ? null : size,
      webViewLink: null,
      webContentLink: null,
    );
  }

  Map<String, dynamic> _decodeAnyMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  String _guessMimeTypeByName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.wmv') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.mpg') ||
        lower.endsWith('.mpeg') ||
        lower.endsWith('.ts')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.m4a')) {
      return 'audio/mpeg';
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return 'text/plain';
    }
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
      return 'application/zip';
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    return 'application/octet-stream';
  }

  String? _basenameFromPath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    if (segments.isEmpty) {
      return null;
    }
    return segments.last;
  }

  Future<void> _onDriveItemTap(DriveItem item, CloudAccount account) async {
    if (item.isFolder) {
      await _openFolder(item, account);
      return;
    }

    final action = await _showFileActionSheet(item);
    if (action == null) {
      return;
    }

    if (action == _FileAction.open) {
      await _openSelectedFile(item, account);
      return;
    }

    await _downloadSelectedFile(item, account);
  }

  Future<void> _onDriveItemLongPress(
    DriveItem item,
    CloudAccount account,
  ) async {
    if (item.isFolder || !_isImageItem(item)) {
      return;
    }

    try {
      final payload = await _runWithTransferLoader<_CloudFilePayload>(
        message: 'Loading image preview...',
        task: (onProgress) => _fetchCloudFilePayload(
          item: item,
          account: account,
          onProgress: onProgress,
        ),
      );

      if (!mounted) {
        return;
      }

      if (!payload.mimeType.toLowerCase().startsWith('image/')) {
        _showActionNotice('Preview is available only for image files.');
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 40,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 380,
                maxHeight: 500,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      color: const Color(0xFFF8FAFC),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        payload.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: InteractiveViewer(
                          minScale: 0.7,
                          maxScale: 4,
                          child: Image.memory(
                            payload.bytes,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      _showActionNotice('Could not load image preview: $e');
    }
  }

  bool _isImageItem(DriveItem item) {
    final lowerMime = (item.mimeType ?? '').toLowerCase();
    if (lowerMime.startsWith('image/')) {
      return true;
    }

    final lowerName = item.name.toLowerCase();
    return lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.bmp') ||
        lowerName.endsWith('.heic') ||
        lowerName.endsWith('.heif');
  }

  Future<void> _openFolder(DriveItem folder, CloudAccount account) async {
    if (folder.id == null || folder.id!.isEmpty) {
      _showActionNotice('Folder id not available.');
      return;
    }

    switch (account.provider) {
      case CloudProvider.googleDrive:
        await _reloadGoogleDriveFolder(
          account: account,
          folderId: folder.id,
          pushEntry: _FolderPathEntry(id: folder.id!, name: folder.name),
        );
        break;
      case CloudProvider.oneDrive:
        await _reloadOneDriveFolder(
          account: account,
          folderId: folder.id,
          pushEntry: _FolderPathEntry(id: folder.id!, name: folder.name),
        );
        break;
      case CloudProvider.dropbox:
        await _reloadDropboxFolder(
          account: account,
          folderPath: folder.id,
          pushEntry: _FolderPathEntry(id: folder.id!, name: folder.name),
        );
        break;
    }
  }

  Future<void> _navigateUpFolder(CloudAccount account) async {
    final currentPath = List<_FolderPathEntry>.from(
      _folderPathByProvider[account.provider] ?? const <_FolderPathEntry>[],
    );
    if (currentPath.isEmpty) {
      return;
    }
    currentPath.removeLast();
    final parentFolderId = currentPath.isEmpty ? null : currentPath.last.id;

    switch (account.provider) {
      case CloudProvider.googleDrive:
        await _reloadGoogleDriveFolder(
          account: account,
          folderId: parentFolderId,
          replacePath: currentPath,
        );
        break;
      case CloudProvider.oneDrive:
        await _reloadOneDriveFolder(
          account: account,
          folderId: parentFolderId,
          replacePath: currentPath,
        );
        break;
      case CloudProvider.dropbox:
        await _reloadDropboxFolder(
          account: account,
          folderPath: parentFolderId,
          replacePath: currentPath,
        );
        break;
    }
  }

  Future<_FileAction?> _showFileActionSheet(DriveItem item) {
    return showModalBottomSheet<_FileAction>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open'),
                subtitle: const Text('Open inside Moon Drive'),
                onTap: () => Navigator.of(sheetContext).pop(_FileAction.open),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Download'),
                subtitle: const Text('Save a local copy from Moon Drive'),
                onTap: () => Navigator.of(sheetContext).pop(_FileAction.download),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSelectedFile(DriveItem item, CloudAccount account) async {
    await _openFileInApp(item: item, account: account);
  }

  Future<void> _downloadSelectedFile(DriveItem item, CloudAccount account) async {
    final accepted = await _ensureDownloadDisclosureAccepted();
    if (!accepted) {
      return;
    }

    await _downloadFileInApp(item: item, account: account);
  }

  Future<void> _openFileInApp({
    required DriveItem item,
    required CloudAccount account,
  }) async {
    try {
      if (_isLikelyVideoOrAudioItem(item)) {
        final streamSource = await _buildMediaStreamSource(
          item: item,
          account: account,
        );
        if (streamSource != null) {
          if (!mounted) {
            return;
          }
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _InAppStreamingMediaPage(
                source: streamSource,
                onDownload: () => _downloadFileInApp(
                  item: item,
                  account: account,
                ),
              ),
            ),
          );
          return;
        }
      }

      if (_shouldOpenDirectlyByStreaming(item)) {
        final opened = await _openFileByStreaming(item: item, account: account);
        if (!opened) {
          _showActionNotice('No supported app found to open this file type.');
        }
        return;
      }

      final payload = await _runWithTransferLoader<_CloudFilePayload>(
        message: 'Loading file in Moon Drive...',
        task: (onProgress) => _fetchCloudFilePayload(
          item: item,
          account: account,
          onProgress: onProgress,
        ),
      );

      if (!mounted) {
        return;
      }

      if (_shouldOpenWithExternalApp(payload.mimeType, payload.fileName)) {
        final openResult = await _openPayloadInDeviceApp(payload);
        if (!openResult) {
          _showActionNotice('No supported app found to open this file type.');
        }
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _InAppCloudFileViewerPage(
            file: payload,
            onDownload: () => _downloadFileInApp(
              item: item,
              account: account,
            ),
          ),
        ),
      );
    } catch (e) {
      _showActionNotice('Could not open file in-app: $e');
    }
  }

  bool _shouldOpenDirectlyByStreaming(DriveItem item) {
    if (_isLikelyVideoOrAudioItem(item)) {
      return false;
    }
    final isLarge = (item.sizeBytes ?? 0) >= _largeFileStreamingThresholdBytes;
    final lowerMime = (item.mimeType ?? '').toLowerCase();
    final lowerName = item.name.toLowerCase();
    final isArchive =
        lowerMime.contains('zip') ||
        lowerMime.contains('rar') ||
        lowerMime.contains('7z') ||
        lowerName.endsWith('.zip') ||
        lowerName.endsWith('.rar') ||
        lowerName.endsWith('.7z');
    return isLarge || item.opensExternallyPreferred || isArchive;
  }

  bool _isLikelyVideoOrAudioItem(DriveItem item) {
    final mime = (item.mimeType ?? '').toLowerCase();
    if (mime.startsWith('video/') || mime.startsWith('audio/')) {
      return true;
    }

    final name = item.name.toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.mkv') ||
        name.endsWith('.mov') ||
        name.endsWith('.avi') ||
        name.endsWith('.webm') ||
        name.endsWith('.3gp') ||
        name.endsWith('.m4v') ||
        name.endsWith('.wmv') ||
        name.endsWith('.flv') ||
        name.endsWith('.mpg') ||
        name.endsWith('.mpeg') ||
        name.endsWith('.ts') ||
        name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.m4a') ||
        name.endsWith('.aac') ||
        name.endsWith('.ogg') ||
        name.endsWith('.wma') ||
        name.endsWith('.flac');
  }

  Future<_MediaStreamSource?> _buildMediaStreamSource({
    required DriveItem item,
    required CloudAccount account,
  }) async {
    if (item.isFolder || !_isLikelyVideoOrAudioItem(item)) {
      return null;
    }

    final activeAccount = await _ensureActiveAccessToken(account);
    final token = activeAccount.token;
    if (token == null || token.isEmpty) {
      throw CloudAuthException('Session expired. Please login again.');
    }

    final mime = _normalizeMimeType(item.mimeType, fileName: item.name);

    switch (account.provider) {
      case CloudProvider.googleDrive:
        if (_isGoogleWorkspaceDoc(item.mimeType)) {
          return null;
        }
        final itemId = item.id;
        if (itemId == null || itemId.isEmpty) {
          throw CloudAuthException('Google Drive file id not available.');
        }
        return _MediaStreamSource(
          uri: Uri.https(
            'www.googleapis.com',
            '/drive/v3/files/${Uri.encodeComponent(itemId)}',
            <String, String>{'alt': 'media'},
          ),
          headers: <String, String>{'authorization': 'Bearer $token'},
          fileName: item.name,
          mimeType: mime,
        );
      case CloudProvider.oneDrive:
        final itemId = item.id;
        if (itemId == null || itemId.isEmpty) {
          throw CloudAuthException('OneDrive file id not available.');
        }
        return _MediaStreamSource(
          uri: Uri.https(
            'graph.microsoft.com',
            '/v1.0/me/drive/items/${Uri.encodeComponent(itemId)}/content',
          ),
          headers: <String, String>{'authorization': 'Bearer $token'},
          fileName: item.name,
          mimeType: mime,
        );
      case CloudProvider.dropbox:
        final path = item.id;
        if (path == null || path.isEmpty) {
          throw CloudAuthException('Dropbox file path not available.');
        }
        final client = _AccessTokenClient(token);
        try {
          final response = await client
              .post(
                Uri.https('api.dropboxapi.com', '/2/files/get_temporary_link'),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(<String, String>{'path': path}),
              )
              .timeout(_authRequestTimeout);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw CloudAuthException(
              'Dropbox media link failed (HTTP ${response.statusCode}).',
            );
          }
          final map = _decodeAnyMap(response.body);
          final link = (map['link'] as String?)?.trim();
          if (link == null || link.isEmpty) {
            throw CloudAuthException('Dropbox media link not returned.');
          }
          return _MediaStreamSource(
            uri: Uri.parse(link),
            fileName: item.name,
            mimeType: mime,
          );
        } finally {
          client.close();
        }
    }
  }

  bool _shouldOpenWithExternalApp(String mimeType, String fileName) {
    final lowerMime = mimeType.toLowerCase();
    final lowerName = fileName.toLowerCase();
    return lowerMime.contains('wordprocessingml') ||
        lowerMime.contains('msword') ||
        lowerMime.contains('presentationml') ||
        lowerMime.contains('powerpoint') ||
        lowerMime.contains('spreadsheetml') ||
        lowerMime.contains('ms-excel') ||
        lowerName.endsWith('.doc') ||
        lowerName.endsWith('.docx') ||
        lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pptx') ||
        lowerName.endsWith('.xls') ||
        lowerName.endsWith('.xlsx');
  }

  Future<bool> _openPayloadInDeviceApp(_CloudFilePayload payload) async {
    try {
      final file = await _writeOpenedTempFile(
        preferredName: payload.fileName,
        bytes: payload.bytes,
      );

      final result = await OpenFilex.open(file.path);
      if (result.type == ResultType.done) {
        _scheduleOpenedTempFileCleanup(file);
      } else {
        await _deleteFileQuietly(file);
      }
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

    Future<void> _downloadFileInApp({
    required DriveItem item,
    required CloudAccount account,
    }) async {
    try {
          final stagingDir = await _resolveDownloadStagingDirectory();
      final outputFile = await _runWithTransferLoader<File>(
        message: 'Preparing download...',
        task: (onProgress) => _downloadFileByStreaming(
          item: item,
          account: account,
              outputDirectory: stagingDir,
          preferDownloadExport: true,
          onProgress: onProgress,
        ),
      );

          final safeName = outputFile.uri.pathSegments.isEmpty
              ? _sanitizeFileName(item.name)
              : outputFile.uri.pathSegments.last;

              final mimeType =
                  item.mimeType?.trim().isNotEmpty == true
                      ? item.mimeType!.trim()
                      : 'application/octet-stream';
      String? finalTarget;
      try {
        finalTarget = await _persistDownloadedFileToPublicDownloads(
          sourceFile: outputFile,
          fileName: safeName,
          mimeType: mimeType,
        );
        if (Platform.isAndroid && finalTarget == null) {
          throw CloudAuthException(
            'Could not save the file into Downloads/MoonDrive Downloads.',
          );
        }
        finalTarget ??= outputFile.path;
      } finally {
        await _deleteFileQuietly(outputFile);
          }

          _showActionNotice('Downloaded to Downloads/MoonDrive Downloads');
      await _showDownloadCompletedNotification(
            fileTarget: finalTarget,
        fileName: safeName,
            mimeType: mimeType,
      );
    } catch (e) {
      _showActionNotice('Download failed: $e');
    }
    }

  Future<bool> _openFileByStreaming({
    required DriveItem item,
    required CloudAccount account,
  }) async {
    try {
      final tempDir = await _resolveOpenedTempDirectory();
      final outputFile = await _runWithTransferLoader<File>(
        message: 'Opening file...',
        task: (onProgress) => _downloadFileByStreaming(
          item: item,
          account: account,
          outputDirectory: tempDir,
          preferDownloadExport: false,
          onProgress: onProgress,
        ),
      );
      final result = await OpenFilex.open(outputFile.path);
      if (result.type == ResultType.done) {
        _scheduleOpenedTempFileCleanup(outputFile);
      } else {
        await _deleteFileQuietly(outputFile);
      }
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  Future<File> _downloadFileByStreaming({
    required DriveItem item,
    required CloudAccount account,
    required Directory outputDirectory,
    required bool preferDownloadExport,
    void Function(_TransferProgress progress)? onProgress,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = await _buildCloudDownloadRequest(
        item: item,
        account: account,
        preferDownloadExport: preferDownloadExport,
        forceRefreshToken: attempt == 1,
      );

      final safeName = _sanitizeFileName(request.fileName);
      final outputPath =
          '${outputDirectory.path}${Platform.pathSeparator}$safeName';
      final outputFile = File(outputPath);

      final client = _AccessTokenClient(request.accessToken);
      IOSink? sink;
      try {
        final httpRequest = http.Request(request.method, request.uri)
          ..headers.addAll(request.headers);
        final streamedResponse = await client.send(httpRequest);
        if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
          final rawError = await streamedResponse.stream.bytesToString();
          throw CloudAuthException(
            'Request failed (HTTP ${streamedResponse.statusCode})${rawError.trim().isEmpty ? '' : ': ${rawError.trim()}'}',
          );
        }

        sink = outputFile.openWrite();
        final totalBytes = streamedResponse.contentLength;
        var loadedBytes = 0;
        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          loadedBytes += chunk.length;
          onProgress?.call(
            _TransferProgress(
              loadedBytes: loadedBytes,
              totalBytes: totalBytes,
              fraction: totalBytes != null && totalBytes > 0
                  ? (loadedBytes / totalBytes)
                  : null,
            ),
          );
        }
        await sink.flush();
        await sink.close();
        sink = null;

        onProgress?.call(
          _TransferProgress(
            loadedBytes: loadedBytes,
            totalBytes: totalBytes,
            fraction: totalBytes != null && totalBytes > 0 ? 1 : null,
          ),
        );
        return outputFile;
      } on CloudAuthException catch (e) {
        if (attempt == 0 && _isTokenUnauthorizedError(e)) {
          continue;
        }
        rethrow;
      } finally {
        await sink?.close();
        client.close();
      }
    }

    throw CloudAuthException('Request failed. Please login again.');
  }

  Future<_CloudDownloadRequest> _buildCloudDownloadRequest({
    required DriveItem item,
    required CloudAccount account,
    required bool preferDownloadExport,
    required bool forceRefreshToken,
  }) async {
    final active = await _ensureActiveAccessToken(
      account,
      forceRefresh: forceRefreshToken,
    );
    final token = active.token;
    if (token == null || token.isEmpty) {
      throw CloudAuthException('Session expired. Please login again.');
    }

    switch (account.provider) {
      case CloudProvider.googleDrive:
        final itemId = item.id;
        if (itemId == null || itemId.isEmpty) {
          throw CloudAuthException('Google Drive file id not available.');
        }

        final sourceName = item.name.trim().isEmpty
            ? 'file_${DateTime.now().millisecondsSinceEpoch}'
            : item.name.trim();
        String targetName = sourceName;
        Uri requestUri;
        if (_isGoogleWorkspaceDoc(item.mimeType)) {
          final exportMime = _googleExportMimeType(
            item.mimeType,
            preferDownloadExport: preferDownloadExport,
          );
          if (exportMime == null) {
            throw CloudAuthException(
              'This Google file type is not supported for this action.',
            );
          }
          final extension = _extensionForMime(exportMime);
          if (extension != null && !targetName.toLowerCase().endsWith('.$extension')) {
            targetName = '$targetName.$extension';
          }
          requestUri = Uri.https(
            'www.googleapis.com',
            '/drive/v3/files/${Uri.encodeComponent(itemId)}/export',
            <String, String>{'mimeType': exportMime},
          );
        } else {
          requestUri = Uri.https(
            'www.googleapis.com',
            '/drive/v3/files/${Uri.encodeComponent(itemId)}',
            <String, String>{'alt': 'media'},
          );
        }

        return _CloudDownloadRequest(
          method: 'GET',
          uri: requestUri,
          headers: const <String, String>{},
          fileName: targetName,
          accessToken: token,
        );
      case CloudProvider.oneDrive:
        final itemId = item.id;
        if (itemId == null || itemId.isEmpty) {
          throw CloudAuthException('OneDrive file id not available.');
        }
        return _CloudDownloadRequest(
          method: 'GET',
          uri: Uri.https(
            'graph.microsoft.com',
            '/v1.0/me/drive/items/${Uri.encodeComponent(itemId)}/content',
          ),
          headers: const <String, String>{},
          fileName: item.name,
          accessToken: token,
        );
      case CloudProvider.dropbox:
        final filePath = item.id;
        if (filePath == null || filePath.isEmpty) {
          throw CloudAuthException('Dropbox file path not available.');
        }
        return _CloudDownloadRequest(
          method: 'POST',
          uri: Uri.https('content.dropboxapi.com', '/2/files/download'),
          headers: <String, String>{
            'Dropbox-API-Arg': jsonEncode(<String, String>{'path': filePath}),
          },
          fileName: item.name,
          accessToken: token,
        );
    }
  }

  Future<Directory> _resolveDownloadStagingDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final staging = Directory(
      '${tempDir.path}${Platform.pathSeparator}$_downloadStagingDirName',
    );
    if (!await staging.exists()) {
      await staging.create(recursive: true);
    }
    return staging;
  }

  Future<String?> _persistDownloadedFileToPublicDownloads({
    required File sourceFile,
    required String fileName,
    required String mimeType,
  }) async {
    if (!Platform.isAndroid) {
      final downloadsDir = await _resolveMoonDriveDownloadsDirectory();
      final target = File(
        '${downloadsDir.path}${Platform.pathSeparator}${_sanitizeFileName(fileName)}',
      );
      await target.writeAsBytes(await sourceFile.readAsBytes(), flush: true);
      return target.path;
    }

    try {
      final result = await _androidStorageChannel.invokeMethod<String>(
        'saveToPublicDownloads',
        <String, dynamic>{
          'sourcePath': sourceFile.path,
          'fileName': _sanitizeFileName(fileName),
          'mimeType': mimeType,
          'folderName': 'MoonDrive Downloads',
        },
      );
      return result;
    } catch (e) {
      debugPrint('Saving to public Downloads failed: $e');
      return null;
    }
  }

    Future<Directory> _resolveMoonDriveDownloadsDirectory() async {
    // Use a dedicated app folder name for all provider downloads.
    final folderName = 'MoonDrive Downloads';

    if (Platform.isAndroid) {
      final publicDownloadsDir = await getDownloadsDirectory();
      if (publicDownloadsDir != null) {
        final preferred = Directory(
          '${publicDownloadsDir.path}${Platform.pathSeparator}$folderName',
        );
        if (!await preferred.exists()) {
          await preferred.create(recursive: true);
        }
        return preferred;
      }

      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final marker =
            '${Platform.pathSeparator}Android${Platform.pathSeparator}';
        final markerIndex = externalDir.path.indexOf(marker);
        final storageRoot = markerIndex >= 0
            ? externalDir.path.substring(0, markerIndex)
            : externalDir.path;

        final preferred = Directory(
          '$storageRoot${Platform.pathSeparator}Download${Platform.pathSeparator}$folderName',
        );
        if (!await preferred.exists()) {
          await preferred.create(recursive: true);
        }
        return preferred;
      }
    }

    final appDocsDir = await getApplicationDocumentsDirectory();
    final fallback = Directory(
      '${appDocsDir.path}${Platform.pathSeparator}$folderName',
    );
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback;
    }

  Future<_CloudFilePayload> _fetchCloudFilePayload({
    required DriveItem item,
    required CloudAccount account,
    bool preferDownloadExport = false,
    void Function(_TransferProgress progress)? onProgress,
  }) {
    switch (account.provider) {
      case CloudProvider.googleDrive:
        return _fetchGoogleDriveFilePayload(
          item: item,
          account: account,
          preferDownloadExport: preferDownloadExport,
          onProgress: onProgress,
        );
      case CloudProvider.oneDrive:
        return _fetchOneDriveFilePayload(
          item: item,
          account: account,
          onProgress: onProgress,
        );
      case CloudProvider.dropbox:
        return _fetchDropboxFilePayload(
          item: item,
          account: account,
          onProgress: onProgress,
        );
    }
  }

  Future<T> _runWithTransferLoader<T>({
    required String message,
    required Future<T> Function(
      void Function(_TransferProgress progress) onProgress,
    ) task,
  }) async {
    final progressNotifier = ValueNotifier<_TransferProgress>(
      const _TransferProgress(
        loadedBytes: 0,
        totalBytes: null,
        fraction: null,
      ),
    );
    var loaderVisible = false;
    if (mounted) {
      loaderVisible = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PopScope(
            canPop: false,
            child: AlertDialog(
              content: SizedBox(
                width: 320,
                child: ValueListenableBuilder<_TransferProgress>(
                  valueListenable: progressNotifier,
                  builder: (_, progress, __) {
                    final hasProgress = progress.fraction != null;
                    final safeProgress = hasProgress
                        ? progress.fraction!.clamp(0.0, 1.0).toDouble()
                        : 0.0;
                    final percentText = hasProgress
                        ? '${(safeProgress * 100).toStringAsFixed(0)}%'
                        : 'Calculating...';
                    final bytesText = progress.totalBytes != null
                        ? '${_formatBytes(progress.loadedBytes)} / ${_formatBytes(progress.totalBytes!)}'
                        : '${_formatBytes(progress.loadedBytes)} downloaded';

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: hasProgress ? safeProgress : null,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          percentText,
                          style: const TextStyle(color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bytesText,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    try {
      return await task((progress) {
        progressNotifier.value = progress;
      });
    } finally {
      progressNotifier.dispose();
      if (loaderVisible && mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<_CloudFilePayload> _fetchGoogleDriveFilePayload({
    required DriveItem item,
    required CloudAccount account,
    bool preferDownloadExport = false,
    void Function(_TransferProgress progress)? onProgress,
  }) async {
    final activeAccount = await _ensureActiveAccessToken(account);
    var token = activeAccount.token;
    if (token == null || token.isEmpty) {
      throw CloudAuthException('Google Drive token is missing. Please login again.');
    }
    final itemId = item.id;
    if (itemId == null || itemId.isEmpty) {
      throw CloudAuthException('Google Drive file id not available.');
    }

    final sourceName = item.name.trim().isEmpty
        ? 'file_${DateTime.now().millisecondsSinceEpoch}'
        : item.name.trim();

    String targetMime = item.mimeType ?? 'application/octet-stream';
    String targetName = sourceName;
    Uri requestUri;

    final isWorkspaceDoc = _isGoogleWorkspaceDoc(item.mimeType);
    if (isWorkspaceDoc) {
      final exportMime = _googleExportMimeType(
        item.mimeType,
        preferDownloadExport: preferDownloadExport,
      );
      if (exportMime == null) {
        throw CloudAuthException(
          'This Google file type is not yet supported for in-app preview/download.',
        );
      }
      targetMime = exportMime;
      final extension = _extensionForMime(exportMime);
      if (extension != null && !targetName.toLowerCase().endsWith('.$extension')) {
        targetName = '$targetName.$extension';
      }

      requestUri = Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/${Uri.encodeComponent(itemId)}/export',
        <String, String>{'mimeType': exportMime},
      );
    } else {
      requestUri = Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/${Uri.encodeComponent(itemId)}',
        <String, String>{'alt': 'media'},
      );
    }

    var retried = false;
    var client = _AccessTokenClient(token);
    try {
      _HttpDownloadResult result;
      try {
        result = await _downloadHttpBytes(
          client: client,
          method: 'GET',
          uri: requestUri,
          onProgress: onProgress,
          errorPrefix: 'Google Drive request failed',
        );
      } on CloudAuthException catch (e) {
        if (!_isTokenUnauthorizedError(e) || retried) {
          rethrow;
        }
        retried = true;
        client.close();
        final refreshed = await _ensureActiveAccessToken(
          activeAccount,
          forceRefresh: true,
        );
        final refreshedToken = refreshed.token;
        if (refreshedToken == null || refreshedToken.isEmpty) {
          throw CloudAuthException('Google Drive session expired. Please login again.');
        }
        token = refreshedToken;
        client = _AccessTokenClient(token);
        result = await _downloadHttpBytes(
          client: client,
          method: 'GET',
          uri: requestUri,
          onProgress: onProgress,
          errorPrefix: 'Google Drive request failed',
        );
      }
      final bytes = result.bytes;
      if (bytes.isEmpty) {
        throw CloudAuthException('Received an empty file from Google Drive.');
      }

      return _CloudFilePayload(
        fileName: targetName,
        mimeType: targetMime,
        bytes: Uint8List.fromList(bytes),
      );
    } finally {
      client.close();
    }
  }

  Future<_CloudFilePayload> _fetchOneDriveFilePayload({
    required DriveItem item,
    required CloudAccount account,
    void Function(_TransferProgress progress)? onProgress,
  }) async {
    final activeAccount = await _ensureActiveAccessToken(account);
    var token = activeAccount.token;
    if (token == null || token.isEmpty) {
      throw CloudAuthException('OneDrive token is missing. Please login again.');
    }
    final itemId = item.id;
    if (itemId == null || itemId.isEmpty) {
      throw CloudAuthException('OneDrive file id not available.');
    }

    final requestUri = Uri.https(
      'graph.microsoft.com',
      '/v1.0/me/drive/items/${Uri.encodeComponent(itemId)}/content',
    );

    var retried = false;
    var client = _AccessTokenClient(token);
    try {
      _HttpDownloadResult result;
      try {
        result = await _downloadHttpBytes(
          client: client,
          method: 'GET',
          uri: requestUri,
          onProgress: onProgress,
          errorPrefix: 'OneDrive request failed',
        );
      } on CloudAuthException catch (e) {
        if (!_isTokenUnauthorizedError(e) || retried) {
          rethrow;
        }
        retried = true;
        client.close();
        final refreshed = await _ensureActiveAccessToken(
          activeAccount,
          forceRefresh: true,
        );
        final refreshedToken = refreshed.token;
        if (refreshedToken == null || refreshedToken.isEmpty) {
          throw CloudAuthException('OneDrive session expired. Please login again.');
        }
        token = refreshedToken;
        client = _AccessTokenClient(token);
        result = await _downloadHttpBytes(
          client: client,
          method: 'GET',
          uri: requestUri,
          onProgress: onProgress,
          errorPrefix: 'OneDrive request failed',
        );
      }
      final bytes = result.bytes;
      if (bytes.isEmpty) {
        throw CloudAuthException('Received an empty file from OneDrive.');
      }

      final responseMime = result.headers['content-type'];
      return _CloudFilePayload(
        fileName: item.name,
        mimeType: _normalizeMimeType(
          responseMime ?? item.mimeType,
          fileName: item.name,
        ),
        bytes: Uint8List.fromList(bytes),
      );
    } finally {
      client.close();
    }
  }

  Future<_CloudFilePayload> _fetchDropboxFilePayload({
    required DriveItem item,
    required CloudAccount account,
    void Function(_TransferProgress progress)? onProgress,
  }) async {
    final activeAccount = await _ensureActiveAccessToken(account);
    var token = activeAccount.token;
    if (token == null || token.isEmpty) {
      throw CloudAuthException('Dropbox token is missing. Please login again.');
    }
    final filePath = item.id;
    if (filePath == null || filePath.isEmpty) {
      throw CloudAuthException('Dropbox file path not available.');
    }

    var retried = false;
    var client = _AccessTokenClient(token);
    try {
      _HttpDownloadResult result;
      try {
        result = await _downloadHttpBytes(
          client: client,
          method: 'POST',
          uri: Uri.https('content.dropboxapi.com', '/2/files/download'),
          headers: <String, String>{
            'Dropbox-API-Arg': jsonEncode(<String, String>{'path': filePath}),
          },
          onProgress: onProgress,
          errorPrefix: 'Dropbox request failed',
        );
      } on CloudAuthException catch (e) {
        if (!_isTokenUnauthorizedError(e) || retried) {
          rethrow;
        }
        retried = true;
        client.close();
        final refreshed = await _ensureActiveAccessToken(
          activeAccount,
          forceRefresh: true,
        );
        final refreshedToken = refreshed.token;
        if (refreshedToken == null || refreshedToken.isEmpty) {
          throw CloudAuthException('Dropbox session expired. Please login again.');
        }
        token = refreshedToken;
        client = _AccessTokenClient(token);
        result = await _downloadHttpBytes(
          client: client,
          method: 'POST',
          uri: Uri.https('content.dropboxapi.com', '/2/files/download'),
          headers: <String, String>{
            'Dropbox-API-Arg': jsonEncode(<String, String>{'path': filePath}),
          },
          onProgress: onProgress,
          errorPrefix: 'Dropbox request failed',
        );
      }
      final bytes = result.bytes;
      if (bytes.isEmpty) {
        throw CloudAuthException('Received an empty file from Dropbox.');
      }

      final apiResult = result.headers['dropbox-api-result'];
      final resultMap = apiResult == null
          ? const <String, dynamic>{}
          : _decodeAnyMap(apiResult);
      final fileName = (resultMap['name'] as String?)?.trim();
      final responseMime = result.headers['content-type'];

      return _CloudFilePayload(
        fileName: (fileName == null || fileName.isEmpty) ? item.name : fileName,
        mimeType: _normalizeMimeType(
          responseMime ?? item.mimeType,
          fileName: (fileName == null || fileName.isEmpty) ? item.name : fileName,
        ),
        bytes: Uint8List.fromList(bytes),
      );
    } finally {
      client.close();
    }
  }

  String _normalizeMimeType(String? raw, {String? fileName}) {
    final normalized = (raw ?? '').split(';').first.trim().toLowerCase();
    final isGeneric =
        normalized.isEmpty ||
        normalized == 'application/octet-stream' ||
        normalized == 'binary/octet-stream' ||
        normalized == 'application/download';

    if (!isGeneric) {
      return normalized;
    }

    final guessed = _guessMimeTypeByName(fileName ?? '');
    return guessed;
  }

  Future<_HttpDownloadResult> _downloadHttpBytes({
    required _AccessTokenClient client,
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    String? body,
    void Function(_TransferProgress progress)? onProgress,
    required String errorPrefix,
  }) async {
    final request = http.Request(method, uri);
    if (headers != null && headers.isNotEmpty) {
      request.headers.addAll(headers);
    }
    if (body != null) {
      request.body = body;
    }

    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawError = await response.stream.bytesToString();
      final compactError = rawError.trim();
      final suffix = compactError.isEmpty ? '' : ': $compactError';
      throw CloudAuthException(
        '$errorPrefix (HTTP ${response.statusCode})$suffix',
      );
    }

    final chunks = <int>[];
    final contentLength = response.contentLength;
    var loaded = 0;

    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
      loaded += chunk.length;

      onProgress?.call(
        _TransferProgress(
          loadedBytes: loaded,
          totalBytes: contentLength,
          fraction: contentLength != null && contentLength > 0
              ? (loaded / contentLength)
              : null,
        ),
      );
    }
    onProgress?.call(
      _TransferProgress(
        loadedBytes: loaded,
        totalBytes: contentLength,
        fraction: contentLength != null && contentLength > 0 ? 1 : null,
      ),
    );

    return _HttpDownloadResult(
      bytes: Uint8List.fromList(chunks),
      headers: response.headers,
    );
  }

  bool _isGoogleWorkspaceDoc(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) {
      return false;
    }
    return mimeType.startsWith('application/vnd.google-apps.') &&
        mimeType != 'application/vnd.google-apps.folder';
  }

  String? _googleExportMimeType(
    String? googleMimeType, {
    required bool preferDownloadExport,
  }) {
    switch (googleMimeType) {
      case 'application/vnd.google-apps.document':
        return preferDownloadExport
            ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            : 'application/pdf';
      case 'application/vnd.google-apps.spreadsheet':
        return 'text/csv';
      case 'application/vnd.google-apps.presentation':
        return 'application/pdf';
      case 'application/vnd.google-apps.drawing':
        return 'image/png';
      case 'application/vnd.google-apps.script':
        return 'application/vnd.google-apps.script+json';
      default:
        return null;
    }
  }

  String? _extensionForMime(String mimeType) {
    switch (mimeType) {
      case 'application/pdf':
        return 'pdf';
      case 'text/plain':
        return 'txt';
      case 'text/csv':
        return 'csv';
      case 'image/png':
        return 'png';
      case 'image/jpeg':
        return 'jpg';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return 'docx';
      case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        return 'xlsx';
      default:
        return null;
    }
  }

  String _sanitizeFileName(String fileName) {
    final sanitized = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (sanitized.isEmpty) {
      return 'download_${DateTime.now().millisecondsSinceEpoch}';
    }
    return sanitized;
  }

  Future<void> _reloadOneDriveFolder({
    required CloudAccount account,
    required String? folderId,
    _FolderPathEntry? pushEntry,
    List<_FolderPathEntry>? replacePath,
  }) async {
    setState(() => _isFolderLoading = true);
    try {
      var authAccount = await _ensureActiveAccessToken(account);
      var token = authAccount.token;
      if (token == null || token.isEmpty) {
        _showActionNotice('Please login again to access OneDrive folders.');
        return;
      }

      List<DriveItem> files;
      try {
        files = await _fetchOneDriveFiles(
          accessToken: token,
          folderId: folderId,
        );
      } catch (e) {
        if (!_isTokenUnauthorizedError(e)) {
          rethrow;
        }
        authAccount = await _ensureActiveAccessToken(
          authAccount,
          forceRefresh: true,
        );
        token = authAccount.token;
        if (token == null || token.isEmpty) {
          _showActionNotice('Please login again to access OneDrive folders.');
          return;
        }
        files = await _fetchOneDriveFiles(
          accessToken: token,
          folderId: folderId,
        );
      }

      if (!mounted) {
        return;
      }

      final updatedPath =
          replacePath ??
          <_FolderPathEntry>[
            ...(_folderPathByProvider[account.provider] ??
                const <_FolderPathEntry>[]),
            if (pushEntry != null) pushEntry,
          ];

      setState(() {
        _replaceAccount(
          authAccount.provider,
          authAccount.copyWith(files: files, clearError: true),
        );
        _folderPathByProvider[account.provider] = updatedPath;
      });
      unawaited(_persistSession());
    } catch (e) {
      _showActionNotice('Unable to open OneDrive folder. $e');
    } finally {
      if (mounted) {
        setState(() => _isFolderLoading = false);
      }
    }
  }

  Future<List<DriveItem>> _fetchOneDriveFiles({
    required String accessToken,
    required String? folderId,
  }) async {
    final client = _AccessTokenClient(accessToken);
    try {
      final endpoint = folderId == null
          ? '/v1.0/me/drive/root/children'
          : '/v1.0/me/drive/items/${Uri.encodeComponent(folderId)}/children';
      final response = await client.get(
        Uri.https('graph.microsoft.com', endpoint, {
          r'$top': '100',
          r'$select': 'id,name,size,file,folder,lastModifiedDateTime,webUrl',
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudAuthException(
          'OneDrive file listing failed (HTTP ${response.statusCode}).',
        );
      }
      final payload = _decodeAnyMap(response.body);
      final items = (payload['value'] as List?) ?? const <dynamic>[];
      return items
          .whereType<Map>()
          .map((raw) => _mapOneDriveListItem(raw.cast<String, dynamic>()))
          .toList();
    } finally {
      client.close();
    }
  }

  Future<void> _reloadDropboxFolder({
    required CloudAccount account,
    required String? folderPath,
    _FolderPathEntry? pushEntry,
    List<_FolderPathEntry>? replacePath,
  }) async {
    setState(() => _isFolderLoading = true);
    try {
      var authAccount = await _ensureActiveAccessToken(account);
      var token = authAccount.token;
      if (token == null || token.isEmpty) {
        _showActionNotice('Please login again to access Dropbox folders.');
        return;
      }

      List<DriveItem> files;
      try {
        files = await _fetchDropboxFiles(
          accessToken: token,
          folderPath: folderPath,
        );
      } catch (e) {
        if (!_isTokenUnauthorizedError(e)) {
          rethrow;
        }
        authAccount = await _ensureActiveAccessToken(
          authAccount,
          forceRefresh: true,
        );
        token = authAccount.token;
        if (token == null || token.isEmpty) {
          _showActionNotice('Please login again to access Dropbox folders.');
          return;
        }
        files = await _fetchDropboxFiles(
          accessToken: token,
          folderPath: folderPath,
        );
      }

      if (!mounted) {
        return;
      }

      final updatedPath =
          replacePath ??
          <_FolderPathEntry>[
            ...(_folderPathByProvider[account.provider] ??
                const <_FolderPathEntry>[]),
            if (pushEntry != null) pushEntry,
          ];

      setState(() {
        _replaceAccount(
          authAccount.provider,
          authAccount.copyWith(files: files, clearError: true),
        );
        _folderPathByProvider[account.provider] = updatedPath;
      });
      unawaited(_persistSession());
    } catch (e) {
      _showActionNotice('Unable to open Dropbox folder. $e');
    } finally {
      if (mounted) {
        setState(() => _isFolderLoading = false);
      }
    }
  }

  Future<List<DriveItem>> _fetchDropboxFiles({
    required String accessToken,
    required String? folderPath,
  }) async {
    final client = _AccessTokenClient(accessToken);
    try {
      var response = await client.post(
        Uri.https('api.dropboxapi.com', '/2/files/list_folder'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(
          <String, dynamic>{
            'path': folderPath ?? '',
            'recursive': false,
            'include_deleted': false,
            'limit': 100,
          },
        ),
      );

      if (response.statusCode >= 300 && (folderPath == null || folderPath.isEmpty)) {
        response = await client.post(
          Uri.https('api.dropboxapi.com', '/2/files/list_folder'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(
            const <String, dynamic>{
              'path': '/',
              'recursive': false,
              'include_deleted': false,
              'limit': 100,
            },
          ),
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudAuthException(
          'Dropbox file listing failed (HTTP ${response.statusCode}).',
        );
      }

      final payload = _decodeAnyMap(response.body);
      final entries = (payload['entries'] as List?) ?? const <dynamic>[];
      return entries
          .whereType<Map>()
          .map((raw) => _mapDropboxListItem(raw.cast<String, dynamic>()))
          .toList();
    } finally {
      client.close();
    }
  }

  Future<void> _reloadGoogleDriveFolder({
    required CloudAccount account,
    required String? folderId,
    _FolderPathEntry? pushEntry,
    List<_FolderPathEntry>? replacePath,
  }) async {
    setState(() => _isFolderLoading = true);
    try {
      var authAccount = await _ensureActiveAccessToken(account);
      var token = authAccount.token;
      if (token == null || token.isEmpty) {
        _showActionNotice('Please login again to access Google Drive folders.');
        return;
      }

      List<DriveItem> files;
      try {
        files = await _fetchGoogleDriveFiles(
          accessToken: token,
          folderId: folderId,
        );
      } catch (e) {
        if (!_isTokenUnauthorizedError(e)) {
          rethrow;
        }
        authAccount = await _ensureActiveAccessToken(
          authAccount,
          forceRefresh: true,
        );
        token = authAccount.token;
        if (token == null || token.isEmpty) {
          _showActionNotice('Please login again to access Google Drive folders.');
          return;
        }
        files = await _fetchGoogleDriveFiles(
          accessToken: token,
          folderId: folderId,
        );
      }

      if (!mounted) {
        return;
      }

      final updatedPath =
          replacePath ??
          <_FolderPathEntry>[
            ...(_folderPathByProvider[account.provider] ??
                const <_FolderPathEntry>[]),
            if (pushEntry != null) pushEntry,
          ];

      setState(() {
        _replaceAccount(
          authAccount.provider,
          authAccount.copyWith(files: files, clearError: true),
        );
        _folderPathByProvider[account.provider] = updatedPath;
      });
      unawaited(_persistSession());
    } catch (e) {
      _showActionNotice('Unable to open folder. $e');
    } finally {
      if (mounted) {
        setState(() => _isFolderLoading = false);
      }
    }
  }

  Future<List<DriveItem>> _fetchGoogleDriveFiles({
    required String accessToken,
    required String? folderId,
  }) async {
    final client = _AccessTokenClient(accessToken);
    try {
      final api = drive.DriveApi(client);
      final query = folderId == null
          ? "trashed = false and 'root' in parents"
          : "trashed = false and '$folderId' in parents";
      final filesResponse = await api.files.list(
        q: query,
        pageSize: 100,
        orderBy: 'folder,name',
        $fields:
            'files(id,name,mimeType,size,modifiedTime,parents,webViewLink,webContentLink)',
      );

      return filesResponse.files?.map((file) {
            final isFolder =
                file.mimeType == 'application/vnd.google-apps.folder';
            final parsedSize = int.tryParse(file.size ?? '0') ?? 0;

            return DriveItem(
              id: file.id,
              name: (file.name == null || file.name!.trim().isEmpty)
                  ? 'Untitled'
                  : file.name!,
              subtitle: isFolder ? 'Folder' : _formatBytes(parsedSize),
              trailingInfo: _formatModifiedDate(file.modifiedTime),
              icon: _iconForMimeType(file.mimeType, isFolder: isFolder),
              iconColor: _colorForMimeType(file.mimeType, isFolder: isFolder),
              mimeType: file.mimeType,
              sizeBytes: isFolder ? null : parsedSize,
              parentIds: List<String>.from(file.parents ?? const <String>[]),
              webViewLink: file.webViewLink,
              webContentLink: file.webContentLink,
            );
          }).toList() ??
          const <DriveItem>[];
    } finally {
      client.close();
    }
  }

  IconData _iconForMimeType(String? mimeType, {required bool isFolder}) {
    if (isFolder) {
      return Icons.folder_outlined;
    }
    final type = (mimeType ?? '').toLowerCase();
    if (type.contains('pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (type.contains('spreadsheet') ||
        type.contains('excel') ||
        type.contains('sheet')) {
      return Icons.table_chart_outlined;
    }
    if (type.contains('presentation') || type.contains('powerpoint')) {
      return Icons.present_to_all_outlined;
    }
    if (type.contains('image')) {
      return Icons.image_outlined;
    }
    return Icons.description_outlined;
  }

  Color _colorForMimeType(String? mimeType, {required bool isFolder}) {
    if (isFolder) {
      return const Color(0xFF2563EB);
    }
    final type = (mimeType ?? '').toLowerCase();
    if (type.contains('pdf')) {
      return const Color(0xFFDC2626);
    }
    if (type.contains('spreadsheet') ||
        type.contains('excel') ||
        type.contains('sheet')) {
      return const Color(0xFF16A34A);
    }
    if (type.contains('presentation') || type.contains('powerpoint')) {
      return const Color(0xFFEA580C);
    }
    if (type.contains('image')) {
      return const Color(0xFF059669);
    }
    return const Color(0xFF1D4ED8);
  }

  String _formatModifiedDate(DateTime? modifiedTime) {
    if (modifiedTime == null) {
      return 'Recently';
    }
    final now = DateTime.now();
    final date = modifiedTime.toLocal();
    final difference = now.difference(date).inDays;

    if (difference <= 0) {
      return 'Today';
    }
    if (difference == 1) {
      return 'Yesterday';
    }

    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(1)} GB';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  void _showAddAccountDialog() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => _AddAccountDialog(
        onConnect: (provider) {
          Navigator.of(context).pop();
          _showLoginDialog(provider);
        },
      ),
    );
  }

  Future<void> _showLoginDialog(CloudProvider provider) async {
    final account = _accounts.firstWhere((item) => item.provider == provider);
    final emailController = TextEditingController(text: account.email ?? '');
    final passwordController = TextEditingController();
    String? localError;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final isOAuthFlow = !_authService.requiresPassword(provider);

            Future<void> submit() async {
              setLocalState(() {
                isSubmitting = true;
                localError = null;
              });

              try {
                final result = await _authService.login(
                  provider: provider,
                  email: emailController.text,
                  password: passwordController.text,
                );

                setState(() {
                  _replaceAccount(
                    provider,
                    account.copyWith(
                      email: result.email,
                      token: result.token,
                      refreshToken: result.refreshToken,
                      tokenExpiryEpochMs: result.tokenExpiryEpochMs,
                      isConnected: true,
                      usedGb: result.usedGb,
                      totalGb: result.totalGb,
                      files: result.files,
                      clearError: true,
                    ),
                  );
                  _selectedAccountIndex = _accounts.indexWhere(
                    (a) => a.provider == provider,
                  );
                  _folderPathByProvider[provider] = const <_FolderPathEntry>[];
                });
                unawaited(_persistSession());

                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${provider.label} connected as ${result.email}.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } on CloudAuthException catch (e) {
                setLocalState(() => localError = e.message);
                setState(() {
                  _replaceAccount(
                    provider,
                    account.copyWith(
                      email: isOAuthFlow
                          ? account.email
                          : (emailController.text.trim().isEmpty
                                ? account.email
                                : emailController.text.trim()),
                      clearToken: true,
                      clearRefreshToken: true,
                      clearTokenExpiry: true,
                      isConnected: false,
                      files: const [],
                      usedGb: 0,
                      lastError: e.message,
                    ),
                  );
                });
                unawaited(_persistSession());
              } finally {
                setLocalState(() => isSubmitting = false);
              }
            }

            return AlertDialog(
              title: Text('Login to ${provider.label}'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isOAuthFlow) ...[
                      Text(
                        'Continue to secure ${provider.label} sign-in. Moon Drive keeps file access inside the app.',
                        style: const TextStyle(color: Color(0xFF334155)),
                      ),
                    ] else ...[
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Storage Email ID',
                          hintText: 'name@example.com',
                        ),
                      ),
                    ],
                    if (_authService.requiresPassword(provider)) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          helperText: 'Demo password: 123456',
                        ),
                      ),
                    ],
                    if (localError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        localError!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : submit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Login'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _replaceAccount(CloudProvider provider, CloudAccount updated) {
    final index = _accounts.indexWhere((item) => item.provider == provider);
    if (index == -1) {
      return;
    }
    _accounts[index] = updated;
  }

  Future<void> _disconnectAccount(CloudProvider provider) async {
    final account = _accounts.firstWhere((item) => item.provider == provider);
    if (!account.isConnected) {
      return;
    }

    try {
      await _authService.disconnect(provider);
    } catch (_) {
      // Continue local cleanup even if provider sign-out fails.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _replaceAccount(
        provider,
        account.copyWith(
          isConnected: false,
          clearToken: true,
          clearRefreshToken: true,
          clearTokenExpiry: true,
          files: const <DriveItem>[],
          usedGb: 0,
          clearError: true,
        ),
      );
      _folderPathByProvider[provider] = const <_FolderPathEntry>[];
    });
    unawaited(_persistSession());
    _showActionNotice('${provider.label} disconnected.');
  }

  Future<bool> _confirmUpload({
    required String accountName,
    required String fileName,
    required int sizeBytes,
    required int fileCount,
    required List<String> fileNames,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final previewNames = fileNames.take(3).toList(growable: false);
        final remaining = fileCount - previewNames.length;
        return AlertDialog(
          title: Text('Upload to $accountName?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileCount == 1
                    ? 'Do you want to upload "$fileName" (${_formatBytes(sizeBytes)})?'
                    : 'Do you want to upload $fileCount files (${_formatBytes(sizeBytes)})?',
              ),
              if (fileCount > 1) ...[
                const SizedBox(height: 12),
                const Text(
                  'Selected files:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...previewNames.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $name'),
                  ),
                ),
                if (remaining > 0) Text('• +$remaining more'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _restorePersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_prefsAccountsKey);
    final selectedIndex = prefs.getInt(_prefsSelectedIndexKey);

    if (encoded == null || encoded.trim().isEmpty) {
      if (selectedIndex != null && mounted) {
        setState(() {
          _selectedAccountIndex = selectedIndex.clamp(0, _accounts.length - 1);
        });
      }
      return;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        return;
      }

      final byProvider = <CloudProvider, Map<String, dynamic>>{};
      for (final raw in decoded) {
        if (raw is! Map) {
          continue;
        }
        final map = raw.cast<String, dynamic>();
        final provider = _providerFromName(map['provider'] as String?);
        if (provider != null) {
          byProvider[provider] = map;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _accounts = _accounts.map((base) {
          final raw = byProvider[base.provider];
          if (raw == null) {
            return base;
          }
          return _deserializeAccount(base: base, raw: raw);
        }).toList();

        if (selectedIndex != null) {
          _selectedAccountIndex = selectedIndex.clamp(0, _accounts.length - 1);
        }
      });
    } catch (_) {
      // Ignore malformed cached session and keep default account state.
    }
  }

  Future<void> _persistSession() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _accounts
        .map((account) => _serializeAccount(account))
        .toList(growable: false);
    await prefs.setString(_prefsAccountsKey, jsonEncode(payload));
    await prefs.setInt(_prefsSelectedIndexKey, _selectedAccountIndex);
  }

  Future<bool> _ensureDownloadDisclosureAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyAccepted =
        prefs.getBool(_prefsDownloadDisclosureAcceptedKey) ?? false;
    if (alreadyAccepted) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Download file?'),
          content: const Text(
            'Files are downloaded only when you choose Download. Moon Drive securely requests the file and saves it in the app storage on your device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    final allow = accepted ?? false;
    if (allow) {
      await prefs.setBool(_prefsDownloadDisclosureAcceptedKey, true);
    }
    return allow;
  }

  CloudProvider? _providerFromName(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    for (final provider in CloudProvider.values) {
      if (provider.name == raw) {
        return provider;
      }
    }
    return null;
  }

  Map<String, dynamic> _serializeAccount(CloudAccount account) {
    return <String, dynamic>{
      'provider': account.provider.name,
      'email': account.email,
      'isConnected': account.isConnected,
      'token': account.token,
      'refreshToken': account.refreshToken,
      'tokenExpiryEpochMs': account.tokenExpiryEpochMs,
      'lastError': account.lastError,
      'usedGb': account.usedGb,
      'totalGb': account.totalGb,
      'files': account.files
          .map((item) => <String, dynamic>{
                'id': item.id,
                'name': item.name,
                'subtitle': item.subtitle,
                'trailingInfo': item.trailingInfo,
                'mimeType': item.mimeType,
                'sizeBytes': item.sizeBytes,
                'parentIds': item.parentIds,
                'webViewLink': item.webViewLink,
                'webContentLink': item.webContentLink,
              })
          .toList(growable: false),
    };
  }

  CloudAccount _deserializeAccount({
    required CloudAccount base,
    required Map<String, dynamic> raw,
  }) {
    final token = raw['token'] as String?;
    final isConnected = (raw['isConnected'] == true) &&
        token != null &&
        token.isNotEmpty;
    final files = _deserializeFiles(raw['files']);

    return base.copyWith(
      email: raw['email'] as String?,
      isConnected: isConnected,
      token: token,
      refreshToken: raw['refreshToken'] as String?,
      tokenExpiryEpochMs: _toIntNullable(raw['tokenExpiryEpochMs']),
      lastError: raw['lastError'] as String?,
      usedGb: _toDouble(raw['usedGb'], fallback: base.usedGb),
      totalGb: _toDouble(raw['totalGb'], fallback: base.totalGb),
      files: files,
    );
  }

  List<DriveItem> _deserializeFiles(dynamic raw) {
    if (raw is! List) {
      return const <DriveItem>[];
    }

    final files = <DriveItem>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = item.cast<String, dynamic>();
      final name = (map['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        continue;
      }
      final mimeType = map['mimeType'] as String?;
      final isFolder = mimeType == 'application/vnd.google-apps.folder';
      files.add(
        DriveItem(
          id: map['id'] as String?,
          name: name,
          subtitle: (map['subtitle'] as String?) ?? (isFolder ? 'Folder' : '-'),
          trailingInfo: (map['trailingInfo'] as String?) ?? 'Recently',
          icon: _iconForMimeType(mimeType, isFolder: isFolder),
          iconColor: _colorForMimeType(mimeType, isFolder: isFolder),
          mimeType: mimeType,
          sizeBytes: _toIntNullable(map['sizeBytes']),
          parentIds: _toStringList(map['parentIds']),
          webViewLink: map['webViewLink'] as String?,
          webContentLink: map['webContentLink'] as String?,
        ),
      );
    }
    return files;
  }

  List<String> _toStringList(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw.whereType<String>().toList(growable: false);
  }

  double _toDouble(dynamic raw, {required double fallback}) {
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw is String) {
      return double.tryParse(raw) ?? fallback;
    }
    return fallback;
  }

  int? _toIntNullable(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }
}

class _InAppCloudFileViewerPage extends StatefulWidget {
  const _InAppCloudFileViewerPage({
    required this.file,
    required this.onDownload,
  });

  final _CloudFilePayload file;
  final Future<void> Function() onDownload;

  @override
  State<_InAppCloudFileViewerPage> createState() =>
      _InAppCloudFileViewerPageState();
}

class _InAppStreamingMediaPage extends StatefulWidget {
  const _InAppStreamingMediaPage({
    required this.source,
    required this.onDownload,
  });

  final _MediaStreamSource source;
  final Future<void> Function() onDownload;

  @override
  State<_InAppStreamingMediaPage> createState() =>
      _InAppStreamingMediaPageState();
}

class _InAppStreamingMediaPageState extends State<_InAppStreamingMediaPage> {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        widget.source.uri,
        httpHeaders: widget.source.headers,
      );
      await controller.initialize();
      await controller.setLooping(false);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.source.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Download',
            onPressed: widget.onDownload,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null || controller == null)
          ? _UnsupportedPreview(
              title: 'Unable to stream media',
              subtitle: _error ?? 'Could not initialize media player.',
            )
          : Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio <= 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(controller),
                    VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF2563EB),
                      ),
                    ),
                    Positioned(
                      bottom: 36,
                      child: FloatingActionButton.small(
                        onPressed: () {
                          setState(() {
                            if (controller.value.isPlaying) {
                              controller.pause();
                            } else {
                              controller.play();
                            }
                          });
                        },
                        child: Icon(
                          controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _InAppCloudFileViewerPageState extends State<_InAppCloudFileViewerPage> {
  VideoPlayerController? _videoController;
  String? _videoLoadError;
  bool _isPreparingVideo = false;
  File? _pdfTempFile;
  String? _pdfLoadError;
  bool _isPreparingPdf = false;
  final List<File> _sessionTempFiles = <File>[];

  @override
  void initState() {
    super.initState();
    final mime = _resolvedMime(widget.file.mimeType, widget.file.fileName);
    if (_isVideoOrAudio(mime)) {
      unawaited(_prepareVideoPlayer());
    } else if (mime.contains('pdf')) {
      unawaited(_preparePdfViewer());
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    for (final file in _sessionTempFiles) {
      unawaited(_deleteTempFile(file));
    }
    super.dispose();
  }

  Future<void> _preparePdfViewer() async {
    if (_isPreparingPdf || _pdfTempFile != null) {
      return;
    }
    setState(() {
      _isPreparingPdf = true;
      _pdfLoadError = null;
    });

    try {
      final file = await _createTempFile(
        widget.file.fileName,
        widget.file.bytes,
      );
      if (!mounted) {
        await _deleteTempFile(file);
        return;
      }

      setState(() {
        _pdfTempFile = file;
        _isPreparingPdf = false;
      });
      _sessionTempFiles.add(file);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pdfLoadError = e.toString();
        _isPreparingPdf = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.file.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Download',
            onPressed: widget.onDownload,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: _buildViewerBody(),
    );
  }

  Widget _buildViewerBody() {
    final mime = _resolvedMime(widget.file.mimeType, widget.file.fileName);

    if (mime.contains('pdf')) {
      if (_pdfLoadError != null) {
        return _UnsupportedPreview(
          title: 'Unable to open PDF',
          subtitle: _pdfLoadError!,
        );
      }
      if (_isPreparingPdf || _pdfTempFile == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return SfPdfViewer.file(_pdfTempFile!);
    }

    if (mime.startsWith('image/')) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: InteractiveViewer(
          minScale: 0.7,
          maxScale: 4,
          child: Image.memory(widget.file.bytes, fit: BoxFit.contain),
        ),
      );
    }

    if (_isOfficeDocOrPresentation(mime, widget.file.fileName)) {
      return _UnsupportedPreview(
        title: 'Open with device app',
        subtitle:
            'This office file opens using installed apps like Word or PowerPoint.',
        actionLabel: 'Open file',
        onAction: _openInDeviceApp,
      );
    }

    if (_isTextLike(mime)) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          utf8.decode(widget.file.bytes, allowMalformed: true),
          style: const TextStyle(fontSize: 14, height: 1.45),
        ),
      );
    }

    if (_isVideoOrAudio(mime)) {
      if (_videoLoadError != null) {
        return _UnsupportedPreview(
          title: 'Cannot play this media file',
          subtitle: _videoLoadError!,
        );
      }
      if (_isPreparingVideo || _videoController == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final controller = _videoController!;
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio <= 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              VideoPlayer(controller),
              VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFF2563EB),
                ),
              ),
              Positioned(
                bottom: 36,
                child: FloatingActionButton.small(
                  onPressed: () {
                    setState(() {
                      if (controller.value.isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    });
                  },
                  child: Icon(
                    controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isOfficeDocOrPresentation(mime, widget.file.fileName)) {
      return _UnsupportedPreview(
        title: 'Opening document with installed app',
        subtitle:
            'Word, PowerPoint, and other office files are opened using apps on your device.',
        actionLabel: 'Open file',
        onAction: _openInDeviceApp,
      );
    }

    return _UnsupportedPreview(
      title: 'Preview not available for this file type',
      subtitle: 'Use Open file to open it with an installed app on your device.',
      actionLabel: 'Open file',
      onAction: _openInDeviceApp,
    );
  }

  String _resolvedMime(String rawMime, String fileName) {
    final normalized = rawMime.split(';').first.trim().toLowerCase();
    final isGeneric =
        normalized.isEmpty ||
        normalized == 'application/octet-stream' ||
        normalized == 'binary/octet-stream' ||
        normalized == 'application/download';
    if (!isGeneric) {
      return normalized;
    }

    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.m4a')) {
      return 'audio/mpeg';
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return normalized.isEmpty ? 'application/octet-stream' : normalized;
  }

  bool _isOfficeDocOrPresentation(String mime, String fileName) {
    final lower = fileName.toLowerCase();
    return mime.contains('wordprocessingml') ||
        mime.contains('msword') ||
        mime.contains('presentationml') ||
        mime.contains('powerpoint') ||
        mime.contains('spreadsheetml') ||
        mime.contains('ms-excel') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.ppt') ||
        lower.endsWith('.pptx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.xlsx');
  }

  Future<void> _openInDeviceApp() async {
    try {
      final file = await _createTempFile(widget.file.fileName, widget.file.bytes);
      _sessionTempFiles.add(file);

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        await _deleteTempFile(file);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.isEmpty
                  ? 'No supported app found to open this file.'
                  : 'Could not open file: ${result.message}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open file: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _prepareVideoPlayer() async {
    setState(() {
      _isPreparingVideo = true;
      _videoLoadError = null;
    });

    try {
      final tempName = '${DateTime.now().millisecondsSinceEpoch}_${widget.file.fileName}';
      final tempFile = await _createTempFile(tempName, widget.file.bytes);
      _sessionTempFiles.add(tempFile);

      final controller = VideoPlayerController.file(tempFile);
      await controller.initialize();
      await controller.setLooping(false);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _videoController = controller;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _videoLoadError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingVideo = false;
        });
      }
    }
  }

  bool _isTextLike(String mime) {
    return mime.startsWith('text/') ||
        mime == 'application/json' ||
        mime == 'application/xml' ||
        mime == 'text/xml' ||
        mime == 'application/javascript';
  }

  bool _isVideoOrAudio(String mime) {
    return mime.startsWith('video/') || mime.startsWith('audio/');
  }

  Future<File> _createTempFile(String name, List<int> bytes) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}moondrive_open_cache',
    );
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    final fileName = safeName.isEmpty
        ? 'file_${DateTime.now().millisecondsSinceEpoch}'
        : safeName;
    final file = File('${cacheDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _deleteTempFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup only.
    }
  }
}

class _UnsupportedPreview extends StatelessWidget {
  const _UnsupportedPreview({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 54, color: Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF475569)),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => onAction!.call(),
                icon: const Icon(Icons.open_in_new),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.accounts,
    required this.selectedAccountIndex,
    required this.onSelect,
    required this.onAddAccount,
    required this.onDisconnect,
  });

  final List<CloudAccount> accounts;
  final int selectedAccountIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddAccount;
  final ValueChanged<CloudProvider> onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.cloud_queue, color: Color(0xFF2563EB)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cloud File Manager',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage files across multiple cloud storage accounts',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAddAccount,
                icon: const Icon(Icons.add),
                label: const Text('Add Account'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Cloud Accounts',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: accounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  final isSelected = index == selectedAccountIndex;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelect(index),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isSelected
                            ? const Color(0xFFE8F0FF)
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF94A3FF)
                              : const Color(0xFFD1D5DB),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(account.icon, color: account.iconColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  account.name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                account.isConnected
                                    ? Icons.check_circle
                                    : Icons.warning_amber_rounded,
                                size: 18,
                                color: account.isConnected
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFCA8A04),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            account.isConnected
                                ? (account.email ?? 'Connected')
                                : (account.lastError ?? 'Not connected'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(100),
                            child: LinearProgressIndicator(
                              value: account.usage,
                              minHeight: 6,
                              backgroundColor: const Color(0xFFD1D5DB),
                              color: const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  account.isConnected
                                      ? '${account.usedGb.toStringAsFixed(1)} GB of ${account.totalGb.toStringAsFixed(0)} GB'
                                      : '0 GB of ${account.totalGb.toStringAsFixed(0)} GB',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                              Text(
                                '${account.usagePercent}% used',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF334155),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (account.isConnected)
                                TextButton(
                                  onPressed: () =>
                                      onDisconnect(account.provider),
                                  child: const Text('Disconnect'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.account});

  final CloudAccount account;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.home_outlined, size: 20, color: Color(0xFF64748B)),
            const SizedBox(width: 6),
            const Text(
              'My Files',
              style: TextStyle(fontSize: 20, color: Color(0xFF475569)),
            ),
            const SizedBox(width: 10),
            Chip(
              avatar: Icon(account.icon, size: 16, color: account.iconColor),
              label: Text(
                account.name,
                style: const TextStyle(fontSize: 12),
              ),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            if (!account.isConnected)
              const Chip(
                label: Text('Disconnected', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          account.isConnected
              ? (account.email ?? '')
              : 'Login required for ${account.name}',
          style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

class _TopActions extends StatelessWidget {
  const _TopActions({
    super.key,
    required this.isCompactLayout,
    required this.isGridView,
    required this.isUploading,
    required this.onSearchChanged,
    required this.onUpload,
    required this.onCreateFolder,
    required this.onGridView,
    required this.onListView,
  });

  final bool isCompactLayout;
  final bool isGridView;
  final bool isUploading;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onUpload;
  final VoidCallback onCreateFolder;
  final VoidCallback onGridView;
  final VoidCallback onListView;

  @override
  Widget build(BuildContext context) {
    if (isCompactLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _SquareIconButton(
                    icon: Icons.upload_file_outlined,
                    onPressed: isUploading ? null : onUpload,
                    backgroundColor: const Color(0xFF0F172A),
                    borderColor: const Color(0xFF0F172A),
                    iconColor: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  _SquareIconButton(
                    icon: Icons.more_vert,
                    onPressed: onCreateFolder,
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                ),
                child: Row(
                  children: [
                    _SquareIconButton(
                      icon: Icons.grid_view_outlined,
                      onPressed: onGridView,
                      isActive: isGridView,
                      size: 32,
                      borderColor: Colors.transparent,
                      backgroundColor: isGridView
                          ? const Color(0xFFE8F0FF)
                          : Colors.transparent,
                    ),
                    _SquareIconButton(
                      icon: Icons.view_list_outlined,
                      onPressed: onListView,
                      isActive: !isGridView,
                      size: 32,
                      borderColor: Colors.transparent,
                      backgroundColor: !isGridView
                          ? const Color(0xFFE8F0FF)
                          : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search files...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 12,
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: isUploading ? null : onUpload,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(isUploading ? 'Uploading...' : 'Upload'),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onCreateFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('New Folder'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 320,
            child: TextField(
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search files...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SquareIconButton(
            icon: Icons.grid_view_outlined,
            onPressed: onGridView,
            isActive: isGridView,
          ),
          const SizedBox(width: 6),
          _SquareIconButton(
            icon: Icons.view_list_outlined,
            onPressed: onListView,
            isActive: !isGridView,
          ),
        ],
      ),
    );
  }
}

class _UploadProgressBanner extends StatelessWidget {
  const _UploadProgressBanner({required this.progress});

  final _UploadProgressSnapshot? progress;

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = progress;
    final hasKnownTotal = snapshot != null && snapshot.totalBytes > 0;
    final progressValue = snapshot?.progressFraction;
    final percentText = snapshot == null
        ? 'Starting upload...'
        : '${snapshot.progressPercent}%';
    final bytesText = snapshot == null
        ? 'Preparing file...'
        : '${_formatBytes(snapshot.uploadedBytes)} / ${_formatBytes(snapshot.totalBytes)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Uploading file, please wait...',
            style: TextStyle(
              color: Color(0xFF1E3A8A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: hasKnownTotal ? progressValue : null,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  bytesText,
                  style: const TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                percentText,
                style: const TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.onPressed,
    this.isActive = false,
    this.size = 40,
    this.backgroundColor,
    this.borderColor,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool isActive;
  final double size;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
          side: BorderSide(
            color:
                borderColor ??
                (isActive
                    ? const Color(0xFF2563EB)
                    : const Color(0xFFD1D5DB)),
          ),
          backgroundColor:
              backgroundColor ??
              (isActive ? const Color(0xFFE8F0FF) : Colors.white),
        ),
        child: Icon(
          icon,
          size: size <= 32 ? 16 : 20,
          color:
              iconColor ??
              (isActive ? const Color(0xFF1D4ED8) : const Color(0xFF334155)),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.isCompact = false,
  });

  final DriveItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE1EA)),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 12,
          vertical: isCompact ? 10 : 10,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: item.iconColor, size: isCompact ? 38 : 36),
            SizedBox(height: isCompact ? 7 : 8),
            Text(
              item.name,
              style: TextStyle(
                fontSize: isCompact ? 14 : 20,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: isCompact ? 2 : 4),
            Text(
              item.subtitle,
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontSize: isCompact ? 12 : 13,
              ),
            ),
            if (item.opensExternallyPreferred) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Text(
                  isCompact ? 'External' : 'Opens externally',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onTap,
    this.onLongPress,
  });

  final DriveItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: Icon(item.icon, color: item.iconColor),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(item.subtitle),
        trailing: Text(
          item.opensExternallyPreferred
              ? '${item.trailingInfo} • External'
              : item.trailingInfo,
          style: TextStyle(
            fontSize: 12,
            color: item.opensExternallyPreferred
                ? const Color(0xFF1D4ED8)
                : null,
            fontWeight: item.opensExternallyPreferred
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F172A),
      ),
    );
  }
}

class _DisconnectedState extends StatelessWidget {
  const _DisconnectedState({
    required this.providerLabel,
    required this.error,
  });

  final String providerLabel;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 36,
                  color: Color(0xFF475569),
                ),
                const SizedBox(height: 12),
                Text(
                  'Login required for $providerLabel',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error ??
                      'Connect this account to browse and manage its files.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: error == null
                        ? const Color(0xFF64748B)
                        : const Color(0xFFDC2626),
                    fontWeight: error == null
                        ? FontWeight.w400
                        : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Use Add Account from the left panel to connect this storage.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyFilesState extends StatelessWidget {
  const _EmptyFilesState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open, size: 42, color: Color(0xFF64748B)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFF64748B))),
        ],
      ),
    );
  }
}

class _ConnectivityBanner extends StatelessWidget {
  const _ConnectivityBanner({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final Color background = isOnline
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFEE2E2);
    final Color border = isOnline
        ? const Color(0xFF86EFAC)
        : const Color(0xFFFCA5A5);
    final Color iconColor = isOnline
        ? const Color(0xFF166534)
        : const Color(0xFF991B1B);
    final String message = isOnline ? 'You\'re online' : 'You\'re offline';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.wifi_outlined : Icons.wifi_off_outlined,
            color: iconColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: iconColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackBar extends StatelessWidget {
  const _FeedbackBar();

  @override
  Widget build(BuildContext context) {
    return Align(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: const [
            Icon(Icons.check_circle, color: Color(0xFF7EE8A0), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Done! How does this look?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.thumb_up_off_alt, color: Colors.white70, size: 18),
            SizedBox(width: 8),
            Icon(Icons.thumb_down_off_alt, color: Colors.white70, size: 18),
            SizedBox(width: 10),
            Icon(Icons.close, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AddAccountDialog extends StatelessWidget {
  const _AddAccountDialog({required this.onConnect});

  final ValueChanged<CloudProvider> onConnect;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Add Cloud Storage Account',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Text(
                  'Connect your cloud storage accounts to manage all your files in one place.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 16),
                ),
                const SizedBox(height: 18),
                for (final provider in CloudProvider.values) ...[
                  _ProviderTile(
                    icon: provider.icon,
                    iconColor: provider.iconColor,
                    title: provider.label,
                    subtitle: provider.connectSubtitle,
                    onConnect: () => onConnect(provider),
                  ),
                  if (provider != CloudProvider.values.last)
                    const SizedBox(height: 10),
                ],
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Privacy Notice\nThis app uses a demo authentication flow.\nUse password 123456 to simulate a successful login.',
                    style: TextStyle(color: Color(0xFF475569), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onConnect,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onConnect,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Connect', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
