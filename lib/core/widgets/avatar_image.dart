import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../data/attachment_cache.dart';
import '../utils/attachment_tag.dart';

/// Turns a picture address into something [AppAvatar] can draw.
///
/// - `/uploads/<name>` (what the server sends): fetched once with no auth
///   header (uploads are public, the random name is the secret), kept on disk
///   by [AttachmentCache] and in memory by Flutter's image cache. The name
///   never changes for a picture, so a new picture is a new address and no
///   version or hash is needed.
/// - `asset:<path>` and `memory:<id>`: the demo's bundled pictures and a
///   picture just cropped, before (or without) a server.
class AvatarImages {
  AvatarImages._();

  /// Set once by the app's initial binding.
  static AttachmentCache? cache;

  static final _memory = <String, Uint8List>{};
  static int _next = 0;

  /// Keeps [bytes] and returns the address that draws them.
  static String registerMemory(Uint8List bytes) {
    final key = 'memory:${_next++}';
    _memory[key] = bytes;
    return key;
  }

  static ImageProvider? providerFor(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('asset:')) return AssetImage(url.substring(6));
    if (url.startsWith('memory:')) {
      final bytes = _memory[url];
      return bytes == null ? null : MemoryImage(bytes);
    }
    final store = cache;
    return store == null ? null : CachedAvatarImage(url, store);
  }
}

class CachedAvatarImage extends ImageProvider<CachedAvatarImage> {
  const CachedAvatarImage(this.url, this.store);

  final String url;
  final AttachmentCache store;

  @override
  Future<CachedAvatarImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedAvatarImage>(this);

  @override
  ImageStreamCompleter loadImage(
    CachedAvatarImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: url,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final tag = AttachmentTag(
      kind: 'image',
      name: 'avatar',
      size: '',
      url: url,
      type: 'image/png',
    );
    final file =
        await store.cached(tag) ??
        await store.fetch(tag, onProgress: (_) {}, cancel: CancelToken());
    final bytes = await file.readAsBytes();
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is CachedAvatarImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
