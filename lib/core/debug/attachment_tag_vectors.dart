import '../../data/attachment_cache.dart';
import '../utils/attachment_tag.dart';

/// Debug-only vectors for [AttachmentTag], run by the /debug/assets screen.
class AttachmentTagVectors {
  AttachmentTagVectors._();

  static const _image =
      '[ATTACHMENT:{"kind":"image","name":"IMG_0042.jpg","size":"1.2 MB","url":"/uploads/9f3a00e1.jpg","type":"image/jpeg"}]';

  static String? _key(String url, [String name = '']) => AttachmentCache.keyFor(
    AttachmentTag(kind: 'file', name: name, size: '', url: url, type: ''),
  );

  static const _sealed =
      '[ATTACHMENT:{"kind":"file","name":"Report.pdf","size":"2.4 MB","url":"/uploads/9f3a00e1.e2e","type":"application/pdf","e2e":{"key":"S0VZ","iv":"SVY"}}]';

  /// (label, passed)
  static List<(String, bool)> run() {
    const sealed = AttachmentTag(
      kind: 'file',
      name: 'Report.pdf',
      size: '2.4 MB',
      url: '/uploads/9f3a00e1.e2e',
      type: 'application/pdf',
      e2eKey: 'S0VZ',
      e2eIv: 'SVY',
    );
    final parsedSealed = AttachmentTag.parse(_sealed);
    final image = AttachmentTag.parse(_image);
    final numeric = AttachmentTag.parse(
      '[ATTACHMENT:{"kind":"file","name":"a.pdf","size":2048,"url":"/uploads/x.pdf","type":"application/pdf"}]',
    );
    final caption = AttachmentTag.parse('look $_image');
    const built = AttachmentTag(
      kind: 'image',
      name: 'IMG_0042.jpg',
      size: '1.2 MB',
      url: '/uploads/9f3a00e1.jpg',
      type: 'image/jpeg',
    );
    var emptyUrlRefused = false;
    try {
      const AttachmentTag(
        kind: 'image',
        name: 'a.jpg',
        size: '',
        url: '',
        type: 'image/jpeg',
      ).build();
    } on FormatException {
      emptyUrlRefused = true;
    }
    final long = AttachmentTag(
      kind: 'image',
      name: 'n' * 3000,
      size: '1 MB',
      url: '/uploads/a.jpg',
      type: 'image/jpeg',
    ).build();
    final braces = AttachmentTag(
      kind: 'file',
      name: 'a}]b.pdf',
      size: '',
      url: '/uploads/a.pdf',
      type: '',
    );
    return [
      ('encrypted tag build matches the web shape', sealed.build() == _sealed),
      (
        'encrypted tag parses with its key',
        parsedSealed?.isEncrypted == true &&
            parsedSealed?.e2eKey == 'S0VZ' &&
            parsedSealed?.e2eIv == 'SVY',
      ),
      ('plain tag has no key', image?.isEncrypted == false),
      (
        'key without iv is not encrypted',
        AttachmentTag.parse(
              '[ATTACHMENT:{"kind":"file","name":"a.pdf","url":"/uploads/a.e2e","e2e":{"key":"S0VZ"}}]',
            )?.isUnreadable ==
            true,
      ),
      (
        'cache key: blob keeps .e2e, never the file ext',
        AttachmentCache.keyFor(sealed) == '9f3a00e1.e2e',
      ),
      (
        'encrypted preview shows the name only after decrypting',
        AttachmentTag.preview(_sealed) == 'Report.pdf',
      ),
      ('image tag parses', image?.isImage == true && image?.size == '1.2 MB'),
      ('numeric size becomes text', numeric?.size == '2 KB'),
      ('caption kept', caption?.caption == 'look'),
      ('build matches the web', built.build() == _image),
      (
        'build then parse',
        AttachmentTag.parse(built.build())?.name == built.name,
      ),
      ('empty url refused', emptyUrlRefused),
      ('long name fits 2000', long.length <= AttachmentTag.maxLength),
      (
        '}] in a name is parsed back',
        AttachmentTag.parse(braces.build()) != null,
      ),
      (
        'missing url is malformed',
        AttachmentTag.parse('[ATTACHMENT:{"kind":"image","name":"a"}]') == null,
      ),
      (
        'empty url is malformed',
        AttachmentTag.parse('[ATTACHMENT:{"kind":"image","url":""}]') == null,
      ),
      (
        'unknown kind is malformed',
        AttachmentTag.parse('[ATTACHMENT:{"kind":"zip","url":"/uploads/a"}]') ==
            null,
      ),
      (
        'bad json is malformed',
        AttachmentTag.parse('[ATTACHMENT:{"kind":}]') == null,
      ),
      ('plain text is not a tag', AttachmentTag.parse('hello') == null),
      ('preview image', AttachmentTag.preview(_image) == 'Photo'),
      (
        'preview file',
        AttachmentTag.preview(
              '[ATTACHMENT:{"kind":"file","name":"a.pdf","url":"/uploads/a.pdf"}]',
            ) ==
            'a.pdf',
      ),
      ('preview plain is null', AttachmentTag.preview('hi') == null),
      (
        'other host refused',
        const AttachmentTag(
              kind: 'image',
              name: '',
              size: '',
              url: 'https://evil.example/uploads/a.jpg',
              type: '',
            ).resolvedUrl ==
            null,
      ),
      (
        'path escape refused',
        const AttachmentTag(
              kind: 'image',
              name: '',
              size: '',
              url: '/uploads/../x',
              type: '',
            ).resolvedUrl ==
            null,
      ),
      (
        'cache key: server name and ext',
        _key('/uploads/9f3a00e1.pdf', 'Report.pdf') == '9f3a00e1.pdf',
      ),
      (
        'cache key: ext lower-cased',
        _key('/uploads/9f3a00e1.docx', 'A.DOCX') == '9f3a00e1.docx',
      ),
      (
        'cache key: sender path never used',
        _key('/uploads/9f3a00e1.pdf', '../../etc/passwd.pdf') == '9f3a00e1.pdf',
      ),
      (
        'cache key: unknown name ext falls back to url ext',
        _key('/uploads/9f3a00e1.pdf', 'evil.apk') == '9f3a00e1.pdf',
      ),
      (
        'cache key: no known ext at all',
        _key('/uploads/abc.exe', 'a.apk') == 'abc',
      ),
      (
        'cache key: name without ext',
        _key('/uploads/abc.txt', 'README') == 'abc.txt',
      ),
      ('cache key: ../ in url refused', _key('/uploads/../x.pdf') == null),
      ('cache key: nested ../ refused', _key('/uploads/a/../b.pdf') == null),
      ('cache key: encoded dots refused', _key('/uploads/%2e%2e.pdf') == null),
      ('cache key: backslash refused', _key('/uploads/a\\b.pdf') == null),
      ('cache key: empty name refused', _key('/uploads/') == null),
      ('cache key: outside /uploads refused', _key('/etc/passwd') == null),
      ('cache key: other folder refused', _key('/files/a.pdf') == null),
      (
        'cache key: other host path outside /uploads refused',
        _key('https://evil.example/x/a.pdf') == null,
      ),
    ];
  }
}
