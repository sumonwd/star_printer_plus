import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'star_printer_plus_platform_interface.dart';

/// An implementation of [StarPrinterPlusPlatform] that uses method channels.
class MethodChannelStarPrinterPlus extends StarPrinterPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('star_printer_plus');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
