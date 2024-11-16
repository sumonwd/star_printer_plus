import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'star_printer_plus_method_channel.dart';

abstract class StarPrinterPlusPlatform extends PlatformInterface {
  /// Constructs a StarPrinterPlusPlatform.
  StarPrinterPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static StarPrinterPlusPlatform _instance = MethodChannelStarPrinterPlus();

  /// The default instance of [StarPrinterPlusPlatform] to use.
  ///
  /// Defaults to [MethodChannelStarPrinterPlus].
  static StarPrinterPlusPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [StarPrinterPlusPlatform] when
  /// they register themselves.
  static set instance(StarPrinterPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
