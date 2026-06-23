import UIKit

/// Saves a downloaded image into the user's Photo Library.
///
/// Requires `NSPhotoLibraryAddUsageDescription` in Info.plist — without it the
/// save call crashes at runtime (not a compile error), so the key is declared
/// in project.yml / Info.plist alongside this type.
final class ImageSaver: NSObject {
    private var completion: ((Error?) -> Void)?

    func save(_ image: UIImage, completion: @escaping (Error?) -> Void) {
        self.completion = completion
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(didFinish(_:error:contextInfo:)), nil)
    }

    @objc private func didFinish(_ image: UIImage, error: Error?, contextInfo: UnsafeRawPointer) {
        completion?(error)
        completion = nil
    }
}
