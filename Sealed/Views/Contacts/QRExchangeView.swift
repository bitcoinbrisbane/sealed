import SwiftUI
import VisionKit
import CoreImage.CIFilterBuiltins
import SealedCore

/// In-person key exchange: each person shows their code and scans the other's.
struct QRExchangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var scanning = false
    @State private var status: String?
    @State private var added: Contact?
    @State private var resolving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("Mode", selection: $scanning) {
                    Text("My code").tag(false)
                    Text("Scan theirs").tag(true)
                }
                .pickerStyle(.segmented)

                if scanning { scanner } else { myCode }

                Spacer()

                if let added {
                    Label("\(added.name) added as verified", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.sAccent)
                }
                if let status {
                    Text(status).font(.footnote).foregroundStyle(Color.sWarn).multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Both scan each other").font(.system(size: 15, weight: .semibold))
                    Text("Each phone fetches the other's full public key, checks it matches the fingerprint in the code, and saves the contact as verified in person.")
                        .font(.system(size: 14)).foregroundStyle(Color.sMuted)
                }
                .card(padding: 14)
            }
            .padding(20)
            .background(Color.sBackground)
            .navigationTitle("Exchange keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    @ViewBuilder private var myCode: some View {
        if let card = model.myContactCard {
            VStack(spacing: 18) {
                QRCodeView(payload: card.payload)
                    .frame(width: 250, height: 250)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityLabel("QR code containing your key fingerprint")
                VStack(spacing: 6) {
                    Text(card.name).font(.system(size: 18, weight: .semibold))
                    Text(card.fingerprint.grouped.replacingOccurrences(of: "  ", with: "\n"))
                        .font(.sMono).foregroundStyle(Color.sSecondary).multilineTextAlignment(.center)
                }
            }
        } else {
            ContentUnavailableView("No key yet", systemImage: "key", description: Text("Set up your PGP key first."))
        }
    }

    @ViewBuilder private var scanner: some View {
        if DataScannerViewController.isSupported {
            QRScanner { payload in handle(payload) }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    if resolving { ProgressView("Fetching key…").padding().background(.ultraThinMaterial, in: Capsule()) }
                }
        } else {
            ContentUnavailableView("Camera unavailable", systemImage: "camera",
                                   description: Text("QR scanning needs a device camera."))
                .frame(height: 360)
        }
    }

    private func handle(_ payload: String) {
        guard !resolving else { return }
        guard let card = ContactCard(payload: payload) else {
            status = "That's not a Sealed contact code."
            return
        }
        if card.fingerprint == model.myKey?.publicKey.fingerprint { return }
        resolving = true
        status = nil
        Task {
            defer { resolving = false }
            do {
                if let contact = try await model.resolve(card) {
                    model.add(contact)
                    added = contact
                    scanning = false
                } else {
                    status = "Couldn't find \(card.name)'s key, or it didn't match the code. Ask them to open Sealed once online."
                }
            } catch {
                status = "Lookup failed: \(error.localizedDescription)"
            }
        }
    }
}

/// Renders a string as a crisp QR code.
struct QRCodeView: View {
    var payload: String

    var body: some View {
        if let image = Self.render(payload) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Color.clear
        }
    }

    static func render(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// VisionKit live QR scanner.
struct QRScanner: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .balanced,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    onScan(value)
                    return
                }
            }
        }
    }
}
