import UIKit
import FirebaseFirestore

/// 画像は Firestore の images コレクションに bytes として保存する（1ドキュメント1MiB上限）
enum ImageCompressor {
    static func jpeg(_ image: UIImage, maxBytes: Int = 900_000, maxDimension: CGFloat) -> Data? {
        var dimension = maxDimension
        for _ in 0..<6 {
            let resized = resize(image, maxDimension: dimension)
            for quality in [0.8, 0.65, 0.5, 0.38] {
                if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                    return data
                }
            }
            dimension *= 0.75
        }
        return nil
    }

    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func cached(_ id: String) -> UIImage? {
        memory.object(forKey: id as NSString)
    }

    func image(for id: String) async -> UIImage? {
        if let image = memory.object(forKey: id as NSString) { return image }
        if let task = inflight[id] { return await task.value }
        let file = directory.appendingPathComponent(id)
        let task = Task<UIImage?, Never> {
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { return image }
            guard let snap = try? await Firestore.firestore().collection("images").document(id).getDocument(),
                  let data = snap.get("data") as? Data,
                  let image = UIImage(data: data) else { return nil }
            try? data.write(to: file)
            return image
        }
        inflight[id] = task
        let image = await task.value
        inflight[id] = nil
        if let image { memory.setObject(image, forKey: id as NSString) }
        return image
    }

    func upload(_ image: UIImage, owner: String, maxDimension: CGFloat) async -> String? {
        let data = await Task.detached(priority: .userInitiated) {
            ImageCompressor.jpeg(image, maxDimension: maxDimension)
        }.value
        guard let data, let stored = UIImage(data: data) else { return nil }
        let ref = Firestore.firestore().collection("images").document()
        ref.write(["data": data, "owner": owner, "createdAt": Timestamp(date: Date())], merge: false)
        memory.setObject(stored, forKey: ref.documentID as NSString)
        try? data.write(to: directory.appendingPathComponent(ref.documentID))
        return ref.documentID
    }

    func clearCache() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
