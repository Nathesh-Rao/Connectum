import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

enum PhotoPickError {
  cameraDenied,
  libraryDenied,
  unavailable,
  unsupported,
  tooLarge,
  unreadable,
}

class PhotoPickException implements Exception {
  const PhotoPickException(this.error, this.message);

  final PhotoPickError error;
  final String message;

  @override
  String toString() => message;
}

/// Where a profile picture comes from: the camera or the photo library.
abstract class ProfilePhotoPicker {
  /// The chosen picture's bytes, or null when the person backed out. Throws
  /// [PhotoPickException].
  Future<Uint8List?> pick(PhotoSource source);
}

class ImageProfilePhotoPicker implements ProfilePhotoPicker {
  ImageProfilePhotoPicker();

  /// The server's limit for an image.
  static const maxBytes = 8 * 1024 * 1024;

  final _picker = ImagePicker();

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    final XFile? file;
    try {
      // maxWidth/Height and a quality make the plugin re-encode as JPEG, which
      // also turns an iPhone HEIC into something the engine can decode.
      file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 3000,
        maxHeight: 3000,
        preferredCameraDevice: CameraDevice.front,
      );
    } on PlatformException catch (e) {
      throw fromPlatform(e, source);
    }
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return checkBytes(bytes);
  }

  /// A refused permission or an unavailable source, in words.
  static PhotoPickException fromPlatform(
    PlatformException e,
    PhotoSource source,
  ) {
    if (e.code == 'camera_access_denied') {
      return const PhotoPickException(
        PhotoPickError.cameraDenied,
        'Camera access is off for Connectum.',
      );
    }
    if (e.code == 'photo_access_denied') {
      return const PhotoPickException(
        PhotoPickError.libraryDenied,
        'Photo access is off for Connectum.',
      );
    }
    return PhotoPickException(
      PhotoPickError.unavailable,
      source == PhotoSource.camera
          ? "The camera isn't available."
          : "The photo library isn't available.",
    );
  }

  /// What the server would refuse, checked before the crop screen: empty,
  /// over 8 MB, or not PNG, JPEG, GIF or WebP by its first bytes.
  static Uint8List checkBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const PhotoPickException(
        PhotoPickError.unreadable,
        "That photo couldn't be read.",
      );
    }
    if (bytes.length > maxBytes) {
      throw const PhotoPickException(
        PhotoPickError.tooLarge,
        'That photo is larger than 8 MB.',
      );
    }
    if (!looksLikeImage(bytes)) {
      throw const PhotoPickException(
        PhotoPickError.unsupported,
        'Only PNG, JPEG, GIF or WebP photos can be used.',
      );
    }
    return bytes;
  }

  static bool looksLikeImage(Uint8List b) {
    bool starts(List<int> magic) =>
        b.length >= magic.length &&
        [
          for (var i = 0; i < magic.length; i++) b[i] == magic[i],
        ].every((x) => x);
    if (starts([0x89, 0x50, 0x4E, 0x47])) return true;
    if (starts([0xFF, 0xD8, 0xFF])) return true;
    if (starts([0x47, 0x49, 0x46, 0x38])) return true;
    return b.length >= 12 &&
        starts([0x52, 0x49, 0x46, 0x46]) &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50;
  }
}

/// For the demo and tests: hands back a fixed picture, or throws.
class FakeProfilePhotoPicker implements ProfilePhotoPicker {
  FakeProfilePhotoPicker({this.bytes, this.error, this.backsOut = false});

  Uint8List? bytes;
  PhotoPickException? error;
  bool backsOut;
  final picked = <PhotoSource>[];

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    picked.add(source);
    final e = error;
    if (e != null) throw e;
    if (backsOut) return null;
    return bytes;
  }
}
