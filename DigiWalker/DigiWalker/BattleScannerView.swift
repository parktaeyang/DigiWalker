import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// Whether the camera scanner can be shown. The decision is a pure function so it can be tested without a camera.
enum BattleCameraAccess: Equatable {
    case checking, ready, denied
    /// This device cannot scan (`DataScannerViewController.isSupported == false`).
    case unsupported
    /// Supported, but not usable right now (Screen Time limits, camera in use by another app, ...).
    case unavailable

    static func decide(status: AVAuthorizationStatus, supported: Bool, available: Bool) -> Self {
        guard supported else { return .unsupported }
        switch status {
        case .authorized: return available ? .ready : .unavailable
        case .denied, .restricted: return .denied
        default: return .checking
        }
    }

    static func current() async -> Self {
        // No permission prompt on a device that could not scan anyway.
        guard DataScannerViewController.isSupported else { return .unsupported }
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
        let result = decide(status: status, supported: DataScannerViewController.isSupported,
                            available: DataScannerViewController.isAvailable)
        return result == .checking ? .denied : result
    }
}

struct BattleScannerView: View {
    let onCode: (String) -> Void
    @State private var access = BattleCameraAccess.checking
    /// Set when the scanner could not start or stopped working; shown with a retry.
    @State private var failure: String?
    @State private var attempt = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            switch access {
            case .checking: ProgressView()
            case .ready:
                if let failure {
                    ContentUnavailableView {
                        Label("스캔을 계속할 수 없어요", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("다시 시도") { self.failure = nil; attempt += 1 }
                        Button("닫기") { dismiss() }
                    }
                } else {
                    ScannerRepresentable(onCode: onCode, onFailure: { failure = $0 }).id(attempt).ignoresSafeArea()
                }
            case .denied:
                ContentUnavailableView {
                    Label("카메라를 쓸 수 없어요", systemImage: "camera.fill")
                } description: {
                    Text("설정에서 카메라 접근을 허용해 주세요.")
                } actions: {
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            case .unsupported:
                ContentUnavailableView("이 기기에서는 QR을 찍을 수 없어요", systemImage: "qrcode.viewfinder")
            case .unavailable:
                ContentUnavailableView {
                    Label("지금은 카메라를 쓸 수 없어요", systemImage: "camera.fill")
                } description: {
                    Text("스크린 타임 제한이나 다른 앱이 카메라를 쓰는 중일 수 있어요.")
                } actions: {
                    Button("다시 확인") { Task { access = await BattleCameraAccess.current() } }
                }
            }
        }
        .task { access = await BattleCameraAccess.current() }
        // Back from Settings (or another app): look again, but never disturb a scanner that is already running.
        .onChange(of: phase) { _, new in
            guard new == .active, access != .ready, access != .checking else { return }
            Task { access = await BattleCameraAccess.current() }
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onFailure: onFailure) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.startIfNeeded(scanner)
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let onFailure: (String) -> Void
        private var delivered = false
        private var failed = false

        init(onCode: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onFailure = onFailure
        }

        /// Starts once; after a result or a failure it never starts again by itself (a retry builds a new scanner).
        func startIfNeeded(_ scanner: DataScannerViewController) {
            guard !delivered, !failed, !scanner.isScanning else { return }
            do {
                try scanner.startScanning()
            } catch {
                fail("카메라 스캔을 시작하지 못했어요. 잠시 뒤 다시 시도해 주세요.")
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items { deliver(item, scanner) }
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            deliver(item, scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            fail("카메라를 쓸 수 없게 됐어요. 다른 앱이 카메라를 쓰고 있지 않은지 확인해 주세요.")
        }

        private func fail(_ message: String) {
            guard !delivered, !failed else { return }
            failed = true
            // Not while SwiftUI is updating views.
            Task { @MainActor in onFailure(message) }
        }

        /// The first QR text wins; the scanner stops and the screen closes the sheet.
        private func deliver(_ item: RecognizedItem, _ scanner: DataScannerViewController) {
            guard !delivered, !failed, case .barcode(let code) = item, let text = code.payloadStringValue else { return }
            delivered = true
            scanner.stopScanning()
            onCode(text)
        }
    }
}
