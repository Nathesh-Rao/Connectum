import 'dart:typed_data';

import '../data/profile_photo/profile_photo_picker.dart';
import 'sample_photos.dart';

/// The demo has no camera or library: either choice hands back a drawn
/// sample, so the crop screen and the upload run end to end offline.
class DemoProfilePhotoPicker implements ProfilePhotoPicker {
  @override
  Future<Uint8List?> pick(PhotoSource source) => SamplePhotos.png(
    source == PhotoSource.camera ? SamplePhoto.portrait : SamplePhoto.landscape,
  );
}
