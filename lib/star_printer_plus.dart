
import 'star_printer_plus_platform_interface.dart';

class StarPrinterPlus {
  Future<String?> getPlatformVersion() {
    return StarPrinterPlusPlatform.instance.getPlatformVersion();
  }
}
