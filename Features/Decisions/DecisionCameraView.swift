@preconcurrency import AVFoundation
import SwiftUI

/// A live camera for the runner. The shutter hands one frame to `onPhoto`; nothing runs per frame.
@MainActor
final class DecisionCamera: NSObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    var onPhoto: ((Data) -> Void)?

    /// Asks for access, wires the back camera and starts the preview. False when access is off or there is no camera.
    func start() async -> Bool {
        guard await AVCaptureDevice.requestAccess(for: .video),
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        let session = session
        await Task.detached { session.startRunning() }.value
        return true
    }

    func stop() {
        let session = session
        Task.detached { session.stopRunning() }
    }

    func capture() { output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self) }
}

extension DecisionCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        Task { @MainActor in self.onPhoto?(data) }
    }
}

/// The live view. SwiftUI has no camera preview, so this is a small UIKit layer host.
private struct DecisionCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class Host: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Host {
        let host = Host()
        host.previewLayer?.session = session
        host.previewLayer?.videoGravity = .resizeAspectFill
        return host
    }

    func updateUIView(_ host: Host, context: Context) {}
}

/// The preview with a shutter and a close button, shown inline in the form.
struct DecisionCameraPanel: View {
    var onPhoto: (Data) -> Void
    var onClose: () -> Void
    @State private var camera = DecisionCamera()
    @State private var unavailable = false

    var body: some View {
        VStack(spacing: 12) {
            if unavailable {
                Label("The camera is off or missing. Allow it in Settings, or add a photo instead.", systemImage: "camera.badge.ellipsis")
                    .foregroundStyle(.secondary)
            } else {
                DecisionCameraPreview(session: camera.session)
                    .frame(height: 280)
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityIdentifier("decisions-camera-preview")
            }
            HStack {
                Button("Close camera", action: onClose).buttonStyle(.bordered)
                Spacer()
                Button { camera.capture() } label: {
                    Label("Take photo", systemImage: "camera.circle.fill").prominentLabel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(unavailable)
                .accessibilityIdentifier("decisions-shutter")
            }
        }
        .task {
            camera.onPhoto = onPhoto
            unavailable = await !camera.start()
        }
        .onDisappear { camera.stop() }
    }
}
