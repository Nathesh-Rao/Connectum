import 'package:connectum/data/profile_photo/profile_photo_picker.dart';
import 'package:connectum/data/repositories/profile_photo_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _status(int? status, {Object? body, DioExceptionType? type}) =>
    DioException(
      requestOptions: RequestOptions(path: '/upload'),
      type: type ?? DioExceptionType.badResponse,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/upload'),
              statusCode: status,
              data: body,
            ),
    );

void main() {
  group('upload error mapping (chat_web_upload.erl)', () {
    ProfilePhotoError of(DioException e) =>
        ProfilePhotoRepositoryImpl.mapUploadError(e).error;

    test(
      '413 too large',
      () => expect(of(_status(413)), ProfilePhotoError.tooLarge),
    );
    test(
      '415 unsupported',
      () => expect(of(_status(415)), ProfilePhotoError.unsupported),
    );
    test(
      '429 rate limit',
      () => expect(of(_status(429)), ProfilePhotoError.rateLimit),
    );
    test('401 sign in, with the server text', () {
      final e = ProfilePhotoRepositoryImpl.mapUploadError(
        _status(401, body: {'error': 'Session expired. Sign in again.'}),
      );
      expect(e.error, ProfilePhotoError.signIn);
      expect(e.message, 'Session expired. Sign in again.');
    });
    test(
      '5xx server',
      () => expect(of(_status(502)), ProfilePhotoError.server),
    );
    test('no answer is a network error', () {
      expect(
        of(_status(null, type: DioExceptionType.connectionError)),
        ProfilePhotoError.network,
      );
    });
    test('400 and anything else fall back to a retry message', () {
      expect(of(_status(400)), ProfilePhotoError.network);
    });
  });

  group('fake repository', () {
    test('upload reports progress and hands back an address', () async {
      final progress = <double>[];
      final repo = FakeProfilePhotoRepository(
        delay: Duration.zero,
        register: (b) => 'memory:${b.length}',
      );
      final url = await repo.upload(
        Uint8List.fromList([1, 2, 3]),
        onProgress: progress.add,
      );
      expect(url, 'memory:3');
      expect(progress.last, 1.0);
      expect(repo.uploads, hasLength(1));
    });

    test('a scripted failure is thrown for upload and for remove', () async {
      final repo = FakeProfilePhotoRepository(
        delay: Duration.zero,
        register: (_) => 'x',
        failure: const ProfilePhotoException(
          ProfilePhotoError.rateLimit,
          'slow down',
        ),
      );
      await expectLater(
        repo.upload(Uint8List(1), onProgress: (_) {}),
        throwsA(isA<ProfilePhotoException>()),
      );
      await expectLater(repo.remove(), throwsA(isA<ProfilePhotoException>()));
      repo.failure = null;
      await repo.remove();
      expect(repo.removes, 1);
    });
  });

  group('picker', () {
    test('camera and photo permission refusals', () {
      final camera = ImageProfilePhotoPicker.fromPlatform(
        PlatformException(code: 'camera_access_denied'),
        PhotoSource.camera,
      );
      expect(camera.error, PhotoPickError.cameraDenied);
      final library = ImageProfilePhotoPicker.fromPlatform(
        PlatformException(code: 'photo_access_denied'),
        PhotoSource.gallery,
      );
      expect(library.error, PhotoPickError.libraryDenied);
    });

    test('any other platform error is "not available"', () {
      final e = ImageProfilePhotoPicker.fromPlatform(
        PlatformException(code: 'boom'),
        PhotoSource.camera,
      );
      expect(e.error, PhotoPickError.unavailable);
      expect(e.message, contains('camera'));
    });

    test('bytes: formats the server takes are accepted', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0]);
      final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39]);
      final webp = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);
      for (final b in [png, jpg, gif, webp]) {
        expect(ImageProfilePhotoPicker.checkBytes(b), b);
      }
    });

    test('bytes: other formats, empty and oversize are refused', () {
      PhotoPickError of(Uint8List b) {
        try {
          ImageProfilePhotoPicker.checkBytes(b);
        } on PhotoPickException catch (e) {
          return e.error;
        }
        fail('accepted');
      }

      expect(
        of(Uint8List.fromList([0x42, 0x4D, 0, 0])),
        PhotoPickError.unsupported,
      );
      expect(of(Uint8List(0)), PhotoPickError.unreadable);
      final big = Uint8List(ImageProfilePhotoPicker.maxBytes + 1)
        ..setAll(0, [0xFF, 0xD8, 0xFF]);
      expect(of(big), PhotoPickError.tooLarge);
    });
  });
}
