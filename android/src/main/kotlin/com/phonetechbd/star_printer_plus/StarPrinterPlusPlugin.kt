package com.phonetechbd.star_printer_plus

import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*
import com.starmicronics.stario10.*

class FlutterStarPrinterPlugin: FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private var printers = mutableMapOf<String, StarPrinter>()
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_star_prnt")
        channel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_star_prnt_events")
        eventChannel.setStreamHandler(this)
        
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "portDiscovery" -> handlePortDiscovery(call, result)
            "connect" -> handleConnect(call, result)
            "disconnect" -> handleDisconnect(call, result)
            "print" -> handlePrint(call, result)
            "checkStatus" -> handleCheckStatus(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handlePortDiscovery(call: MethodCall, result: Result) {
        val type = call.argument<String>("type") ?: return result.error("INVALID_ARGUMENT", "Type is required", null)
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val interfaceType = when(type.uppercase()) {
                    "ALL" -> InterfaceType.All
                    "LAN" -> InterfaceType.Lan
                    "BLUETOOTH" -> InterfaceType.Bluetooth
                    "USB" -> InterfaceType.Usb
                    else -> throw Exception("Unsupported interface type")
                }

                val printers = StarDeviceDiscoveryManager.discover(interfaceType, context)
                val printerList = printers.map { printer ->
                    mapOf(
                        "portName" to printer.identifier,
                        "macAddress" to printer.macAddress,
                        "modelName" to printer.information?.model?.name,
                        "USBSerialNumber" to printer.usbSerialNumber
                    )
                }
                
                withContext(Dispatchers.Main) {
                    result.success(printerList)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("DISCOVERY_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handleConnect(call: MethodCall, result: Result) {
        val portName = call.argument<String>("portName") ?: return result.error("INVALID_ARGUMENT", "Port name is required", null)
        val emulation = call.argument<String>("emulation") ?: return result.error("INVALID_ARGUMENT", "Emulation is required", null)
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                if (printers.containsKey(portName)) {
                    throw Exception("Printer already connected")
                }

                val settings = StarConnectionSettings(detectInterfaceType(portName), portName)
                val printer = StarPrinter(settings, context)
                
                printer.printerDelegate = createPrinterDelegate(portName)
                printer.openAsync().await()
                
                printers[portName] = printer
                
                withContext(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("CONNECTION_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handleDisconnect(call: MethodCall, result: Result) {
        val portName = call.argument<String>("portName") ?: return result.error("INVALID_ARGUMENT", "Port name is required", null)
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val printer = printers[portName] ?: throw Exception("Printer not connected")
                printer.closeAsync().await()
                printers.remove(portName)
                
                withContext(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("DISCONNECTION_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handlePrint(call: MethodCall, result: Result) {
        val portName = call.argument<String>("portName") ?: return result.error("INVALID_ARGUMENT", "Port name is required", null)
        val emulation = call.argument<String>("emulation") ?: return result.error("INVALID_ARGUMENT", "Emulation is required", null)
        val commands = call.argument<List<Map<String, Any>>>("printCommands") ?: return result.error("INVALID_ARGUMENT", "Print commands are required", null)
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val printer = printers[portName] ?: throw Exception("Printer not connected")
                val builder = StarXpandCommand.Builder()
                
                builder.addDocument(createDocumentBuilder(commands))
                
                val printCommands = builder.getCommands()
                printer.printAsync(printCommands).await()
                
                val status = printer.getStatusAsync().await()
                val statusMap = createStatusMap(status)
                
                withContext(Dispatchers.Main) {
                    result.success(statusMap)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("PRINT_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handleCheckStatus(call: MethodCall, result: Result) {
        val portName = call.argument<String>("portName") ?: return result.error("INVALID_ARGUMENT", "Port name is required", null)
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val printer = printers[portName] ?: throw Exception("Printer not connected")
                val status = printer.getStatusAsync().await()
                val statusMap = createStatusMap(status)
                
                withContext(Dispatchers.Main) {
                    result.success(statusMap)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("STATUS_ERROR", e.message, null)
                }
            }
        }
    }

    private fun createDocumentBuilder(commands: List<Map<String, Any>>): StarXpandCommand.DocumentBuilder {
        val documentBuilder = StarXpandCommand.DocumentBuilder()
        val printerBuilder = StarXpandCommand.PrinterBuilder()

        commands.forEach { command ->
            when {
                command.containsKey("appendEncoding") -> {
                    // Handle encoding
                }
                command.containsKey("appendCutPaper") -> {
                    val cutType = when(command["appendCutPaper"] as String) {
                        "FullCut" -> StarXpandCommand.CutType.Full
                        "PartialCut" -> StarXpandCommand.CutType.Partial
                        else -> StarXpandCommand.CutType.Full
                    }
                    printerBuilder.addCut(cutType)
                }
                command.containsKey("openCashDrawer") -> {
                    printerBuilder.addDrawer(StarXpandCommand.DrawerChannel.No1)
                }
                command.containsKey("appendBitmap") -> {
                    // Handle bitmap
                }
                command.containsKey("appendBitmapText") -> {
                    val text = command["appendBitmapText"] as String
                    printerBuilder.addText(text)
                }
                // Add other command handlers
            }
        }

        return documentBuilder.addPrinter(printerBuilder)
    }

    private fun createStatusMap(status: StarPrinterStatus): Map<String, Any> {
        return mapOf(
            "offline" to !status.isOnline,
            "coverOpen" to status.coverOpen,
            "cutterError" to status.cutterError,
            "receiptPaperEmpty" to status.paperEmpty,
            "overTemp" to status.overTemp,
            "isSuccess" to status.isOnline
        )
    }

    private fun createPrinterDelegate(portName: String): PrinterDelegate {
        return object : PrinterDelegate() {
            override fun onStatusChanged(printer: StarPrinter) {
                super.onStatusChanged(printer)
                
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val status = printer.getStatusAsync().await()
                        val statusMap = createStatusMap(status)
                        
                        withContext(Dispatchers.Main) {
                            eventSink?.success(statusMap)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            eventSink?.error("STATUS_ERROR", e.message, null)
                        }
                    }
                }
            }
        }
    }

    private fun detectInterfaceType(portName: String): InterfaceType {
        return when {
            portName.startsWith("TCP:") -> InterfaceType.Lan
            portName.startsWith("BT:") -> InterfaceType.Bluetooth
            portName.startsWith("USB:") -> InterfaceType.Usb
            else -> throw Exception("Unknown interface type")
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
