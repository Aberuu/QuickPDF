export 'file_storage_stub.dart'
    if (dart.library.io) 'file_storage_io.dart'
    if (dart.library.js_interop) 'file_storage_web.dart';
