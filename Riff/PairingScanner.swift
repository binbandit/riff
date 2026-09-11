import SwiftUI
import VisionKit
import Vision

struct PairingScanner: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onFailure: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onFailure: onFailure) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        do { try controller.startScanning() } catch { Task { @MainActor in onFailure(error.localizedDescription) } }
        return controller
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) { }
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) { uiViewController.stopScanning() }
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let onFailure: (String) -> Void
        var scanned = false
        init(onScan: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) { self.onScan = onScan; self.onFailure = onFailure }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue, value.hasPrefix("riff://connect?"), !scanned {
                    scanned = true; dataScanner.stopScanning(); onScan(value); return
                }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) { onFailure("Camera scanning is unavailable. Paste the pairing link instead.") }
    }
}
