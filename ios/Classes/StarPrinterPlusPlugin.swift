import Flutter
import UIKit
import StarIO10

public class FlutterStarPrinterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var printers: [String: StarPrinter] = [:]
    private var eventSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_star_prnt", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "flutter_star_prnt_events", binaryMessenger: registrar.messenger())
        
        let instance = FlutterStarPrinterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "portDiscovery":
            handlePortDiscovery(call, result: result)
        case "connect":
            handleConnect(call, result: result)
        case "disconnect":
            handleDisconnect(call, result: result)
        case "print":
            handlePrint(call, result: result)
        case "checkStatus":
            handleCheckStatus(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handlePortDiscovery(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let typeString = arguments["type"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Type is required", details: nil))
            return
        }
        
        Task {
            do {
                let interfaceType = try getInterfaceType(from: typeString)
                let printers = try await StarDeviceDiscoveryManager.discover(interfaceType)
                
                let printerList = printers.map { printer -> [String: Any] in
                    return [
                        "portName": printer.identifier,
                        "macAddress": printer.macAddress ?? "",
                        "modelName": printer.information?.model.name ?? "",
                        "USBSerialNumber": printer.usbSerialNumber ?? ""
                    ]
                }
                
                DispatchQueue.main.async {
                    result(printerList)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DISCOVERY_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func handleConnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let portName = arguments["portName"] as? String,
              let emulation = arguments["emulation"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Port name and emulation are required", details: nil))
            return
        }
        
        Task {
            do {
                if printers[portName] != nil {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Printer already connected"])
                }
                
                let interfaceType = try detectInterfaceType(from: portName)
                let settings = StarConnectionSettings(interfaceType: interfaceType, identifier: portName)
                let printer = StarPrinter(settings)
                
                printer.printerDelegate = self
                try await printer.open()
                
                printers[portName] = printer
                
                DispatchQueue.main.async {
                    result(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CONNECTION_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func handleDisconnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let portName = arguments["portName"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Port name is required", details: nil))
            return
        }
        
        Task {
            do {
                guard let printer = printers[portName] else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Printer not connected"])
                }
                await printer.close()
                printers.removeValue(forKey: portName)
                
                DispatchQueue.main.async {
                    result(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DISCONNECTION_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func handlePrint(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let portName = arguments["portName"] as? String,
              let emulation = arguments["emulation"] as? String,
              let commands = arguments["printCommands"] as? [[String: Any]] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        Task {
            do {
                guard let printer = printers[portName] else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Printer not connected"])
                }
                
                let builder = StarXpandCommand.Builder()
                builder.addDocument(createDocumentBuilder(from: commands))
                
                let printCommands = try builder.getCommands()
                try await printer.print(printCommands)
                
                let status = try await printer.getStatus()
                let statusMap = createStatusMap(from: status)
                
                DispatchQueue.main.async {
                    result(statusMap)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "PRINT_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func handleCheckStatus(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let portName = arguments["portName"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Port name is required", details: nil))
            return
        }
        
        Task {
            do {
                guard let printer = printers[portName] else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Printer not connected"])
                }
                
                let status = try await printer.getStatus()
                let statusMap = createStatusMap(from: status)
                
                DispatchQueue.main.async {
                    result(statusMap)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "STATUS_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func createDocumentBuilder(from commands: [[String: Any]]) -> StarXpandCommand.DocumentBuilder {
        let documentBuilder = StarXpandCommand.DocumentBuilder()
        let printerBuilder = StarXpandCommand.PrinterBuilder()
        
        for command in commands {
            if let encoding = command["appendEncoding"] as? String {
                // Handle encoding
                handleEncoding(encoding, printerBuilder: printerBuilder)
            }
            else if let cutPaper = command["appendCutPaper"] as? String {
                let cutType: StarXpandCommand.CutType = cutPaper == "FullCut" ? .full : .partial
                printerBuilder.addCut(type: cutType)
            }
            else if let _ = command["openCashDrawer"] as? Int {
                printerBuilder.addDrawer(channel: .no1)
            }
            else if let bitmap = command["appendBitmap"] as? String {
                // Handle bitmap
                handleBitmap(bitmap, command: command, printerBuilder: printerBuilder)
            }
            else if let bitmapText = command["appendBitmapText"] as? String {
                printerBuilder.addText(bitmapText)
            }
            // Add other command handlers
        }
        
        return documentBuilder.addPrinter(printerBuilder)
    }
    
    private func handleEncoding(_ encoding: String, printerBuilder: StarXpandCommand.PrinterBuilder) {
        let charset: String
        switch encoding {
        case "US-ASCII":
            charset = "US-ASCII"
        case "Windows-1252":
            charset = "Windows-1252"
        case "Shift-JIS":
            charset = "Shift-JIS"
        default:
            charset = "UTF-8"
        }
        printerBuilder.addTextEncoding(charset)
    }
    
    private func handleBitmap(_ path: String, command: [String: Any], printerBuilder: StarXpandCommand.PrinterBuilder) {
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        
        let width = command["width"] as? Int ?? 576
        let diffusion = command["diffusion"] as? Bool ?? true
        let alignment = command["alignment"] as? String
        
        let imageAlignment: StarXpandCommand.Alignment
        switch alignment {
        case "Left":
            imageAlignment = .left
        case "Center":
            imageAlignment = .center
        case "Right":
            imageAlignment = .right
        default:
            imageAlignment = .left
        }
        
        printerBuilder.addImage(imageData, width: width, effectiveDots: diffusion)
                     .addAlignment(imageAlignment)
    }
    
    private func createStatusMap(from status: StarPrinterStatus) -> [String: Any] {
        return [
            "offline": !status.isOnline,
            "coverOpen": status.coverOpen,
            "cutterError": status.cutterError,
            "receiptPaperEmpty": status.paperEmpty,
            "overTemp": status.overTemp,
            "isSuccess": status.isOnline
        ]
    }
    
    private func getInterfaceType(from typeString: String) throws -> InterfaceType {
        switch typeString.uppercased() {
        case "ALL":
            return .all
        case "LAN":
            return .lan
        case "BLUETOOTH":
            return .bluetooth
        case "USB":
            return .usb
        default:
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported interface type"])
        }
    }
    
    private func detectInterfaceType(from portName: String) throws -> InterfaceType {
        if portName.hasPrefix("TCP:") {
            return .lan
        } else if portName.hasPrefix("BT:") {
            return .bluetooth
        } else if portName.hasPrefix("USB:") {
            return .usb
        }
        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown interface type"])
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

// MARK: - StarPrinterDelegate

extension FlutterStarPrinterPlugin: StarPrinterDelegate {
    public func printerDidChangeStatus(_ printer: StarPrinter) {
        Task {
            do {
                let status = try await printer.getStatus()
                let statusMap = createStatusMap(from: status)
                
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(statusMap)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(FlutterError(code: "STATUS_ERROR", 
                                                message: error.localizedDescription, 
                                                details: nil))
                }
            }
        }
    }
}