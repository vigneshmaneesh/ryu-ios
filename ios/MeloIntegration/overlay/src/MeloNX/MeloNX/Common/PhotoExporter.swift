import Foundation
import Photos
import UIKit

@MainActor
enum PhotoExporter {
    private static var registered = false
    private static let encoderQueue = DispatchQueue(label: "MeloNX.imageExport", qos: .utility)
    private static var waiting: [URL] = []
    private static var exporting = false
    nonisolated private static var captureDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("screenshots")
    }

    static func register() {
        guard !registered else { return }
        registered = true
        CallbackManager.register(name: "ExportImageCapture", handler: receive)
    }

    nonisolated private static func receive(_ data: CallbackData) {
        autoreleasepool {
            guard let pointer = data.ptr,
                  data.len >= MemoryLayout<ImageCaptureRequest>.size else { return }
            let request = pointer.assumingMemoryBound(to: ImageCaptureRequest.self)
            request.pointee.result = 0
            guard let jpeg = CaptureImageEncoder.jpeg(request.pointee) else { return }
            let suppliedPath = request.pointee.filePath.map { String(cString: $0) }
            // Preserve an album copy even when Photos access is denied.
            let file = suppliedPath.map { URL(fileURLWithPath: $0) }
                ?? captureDirectory
                    .appendingPathComponent("Screenshot-\(UUID().uuidString).jpg")
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try jpeg.write(to: file, options: .atomic)
                request.pointee.result = 1
                Task { @MainActor in enqueue(file) }
            } catch {
                print("[Photos] Local capture failed: \(error.localizedDescription)")
                Task { @MainActor in showFailure("Could not save the picture. \(error.localizedDescription)") }
            }
        }
    }

    static func save(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            showFailure("Could not prepare this picture.")
            return
        }
        let file = captureDirectory
            .appendingPathComponent("Picture-\(UUID().uuidString).jpg")
        encoderQueue.async {
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                Task { @MainActor in enqueue(file) }
            } catch {
                Task { @MainActor in showFailure("Could not save the picture. \(error.localizedDescription)") }
            }
        }
    }

    private static func enqueue(_ file: URL) {
        waiting.append(file)
        if !exporting {
            exporting = true
            Task { await drain() }
        }
    }

    private static func drain() async {
        defer { exporting = false }
        while !waiting.isEmpty {
            let files = waiting
            waiting.removeAll()
            var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if status == .notDetermined {
                status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            }
            guard status == .authorized || status == .limited else {
                showFailure("Photos access is off. Your pictures are still in the MeloNX folder. Enable Add Photos in iOS Settings to export them.", offerSettings: true)
                continue
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for file in files {
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: .photo, fileURL: file, options: nil)
                    }
                }
                showNotice(files.count == 1 ? "Picture saved to Photos" : "\(files.count) pictures saved to Photos")
            } catch {
                showFailure("Photos could not save the picture. A copy remains in the MeloNX folder. \(error.localizedDescription)")
            }
        }
    }

    private static func showFailure(_ message: String, offerSettings: Bool = false) {
        var actions: [(title: String, style: UIAlertAction.Style, handler: (() -> Void)?)] = [
            ("OK", .cancel, nil)
        ]
        if offerSettings {
            actions.append(("Open Settings", .default, {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }))
        }
        AppAlerts.showAlert(title: "Save to Photos", message: message, actions: actions)
    }

    private static func showNotice(_ message: String) {
        guard let view = AppAlerts.topViewController()?.view else { return }
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = .black.withAlphaComponent(0.8)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            label.heightAnchor.constraint(equalToConstant: 44),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -24),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])
        UIAccessibility.post(notification: .announcement, argument: message)
        UIView.animate(withDuration: 0.3, delay: 2.5, options: []) {
            label.alpha = 0
        } completion: { _ in label.removeFromSuperview() }
    }
}
