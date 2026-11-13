import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';

enum ProfilePhotoError {
  tooLarge,
  unsupported,
  network,
  rateLimit,
  signIn,
  server,
}

class ProfilePhotoException implements Exception {
  const ProfilePhotoException(this.error, this.message);

  final ProfilePhotoError error;
  final String message;

  @override
  String toString() => message;
}

/// Changes the signed-in person's own picture. Upload then `/setavatar`
/// (contract: `mobile-handoff/profile-picture.md`).
abstract class ProfilePhotoRepository {
  /// Uploads [bytes] (a PNG, JPEG, GIF or WebP) and makes it the picture.
  /// Returns the picture's address (`/uploads/<name>`).
  Future<String> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
    CancelToken? cancel,
  });

  /// Removes the picture.
  Future<void> remove();
}

class ProfilePhotoRepositoryImpl implements ProfilePhotoRepository {
  ProfilePhotoRepositoryImpl(this._dio, this._session, this._socket);

  final Dio _dio;
  final SessionStore _session;
  final SocketService _socket;

  static const notConnected = ProfilePhotoException(
    ProfilePhotoError.network,
    'You are offline. Connect and try again.',
  );

  @override
  Future<String> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
    CancelToken? cancel,
  }) async {
    if (!AppConfig.isConfigured) {
      throw const ProfilePhotoException(
        ProfilePhotoError.server,
        'No server is set up for this build.',
      );
    }
    final token = _session.token;
    final origin = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final String url;
    try {
      final response = await _dio.post<Object?>(
        '$origin/upload',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            bytes,
            filename: 'avatar.png',
            contentType: DioMediaType.parse('image/png'),
          ),
        }),
        options: Options(
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
          responseType: ResponseType.json,
        ),
        cancelToken: cancel,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress((sent / total).clamp(0.0, 1.0));
        },
      );
      final data = response.data;
      final value = data is Map ? data['url'] : null;
      if (value is! String || !value.startsWith('/uploads/')) {
        throw const ProfilePhotoException(
          ProfilePhotoError.server,
          'The server gave an unexpected answer. Try again.',
        );
      }
      url = value;
    } on DioException catch (e) {
      throw mapUploadError(e);
    }
    if (!await _socket.sendCommand('/setavatar $url')) throw notConnected;
    return url;
  }

  @override
  Future<void> remove() async {
    if (!await _socket.sendCommand('/removeavatar')) throw notConnected;
  }

  /// The upload's refusals in words (`chat_web_upload.erl`: 400, 401, 413,
  /// 415, 429; the body is `{"error": text}`).
  static ProfilePhotoException mapUploadError(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final server = data is Map && data['error'] is String
        ? data['error'] as String
        : null;
    return switch (status) {
      401 => ProfilePhotoException(
        ProfilePhotoError.signIn,
        server ?? 'Sign in again to change your photo.',
      ),
      413 => const ProfilePhotoException(
        ProfilePhotoError.tooLarge,
        'That photo is too large. The limit is 8 MB.',
      ),
      415 => const ProfilePhotoException(
        ProfilePhotoError.unsupported,
        'Only PNG, JPEG, GIF or WebP photos can be used.',
      ),
      429 => const ProfilePhotoException(
        ProfilePhotoError.rateLimit,
        'Too many uploads. Wait a minute and try again.',
      ),
      int s when s >= 500 => const ProfilePhotoException(
        ProfilePhotoError.server,
        "The server couldn't save the photo. Try again.",
      ),
      _ => const ProfilePhotoException(
        ProfilePhotoError.network,
        "The photo couldn't be uploaded. Check your connection and try again.",
      ),
    };
  }
}

/// In memory, for the demo and tests: no server. Hands out `memory:` or
/// `asset:` addresses that [AvatarImages] can draw.
class FakeProfilePhotoRepository implements ProfilePhotoRepository {
  FakeProfilePhotoRepository({
    this.delay = const Duration(milliseconds: 600),
    this.failure,
    required this.register,
  });

  final Duration delay;

  /// When set, the next [upload] and [remove] throw it.
  ProfilePhotoException? failure;

  /// Stores the bytes and returns the address that draws them.
  final String Function(Uint8List bytes) register;

  final uploads = <Uint8List>[];
  int removes = 0;

  @override
  Future<String> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
    CancelToken? cancel,
  }) async {
    for (final step in [0.3, 0.7, 1.0]) {
      await Future<void>.delayed(delay ~/ 3);
      onProgress(step);
    }
    final error = failure;
    if (error != null) throw error;
    uploads.add(bytes);
    return register(bytes);
  }

  @override
  Future<void> remove() async {
    await Future<void>.delayed(delay ~/ 3);
    final error = failure;
    if (error != null) throw error;
    removes++;
  }
}
