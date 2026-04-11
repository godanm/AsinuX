// Conditional export: use real AdMob on mobile, stub on web.
export 'admob_service_mobile.dart'
    if (dart.library.html) 'admob_service_stub.dart';
