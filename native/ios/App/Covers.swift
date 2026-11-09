import CommonCrypto
import UIKit

enum Covers {
    private static let cache = NSCache<NSString, UIImage>()
    private static let key = Array("f5d965df75336270".utf8)
    private static let iv = Array("97b60394abc2fbe1".utf8)

    static func clear() { cache.removeAllObjects() }

    static func load(_ url: String, api: HgApi) async -> UIImage? {
        guard !url.isEmpty else { return nil }
        if let hit = cache.object(forKey: url as NSString) { return hit }
        guard let data = try? await api.bytes(url) else { return nil }
        let plain = looksImage(data) ? data : (decrypt(data) ?? data)
        guard let image = UIImage(data: plain) else { return nil }
        cache.setObject(image, forKey: url as NSString)
        return image
    }

    private static func looksImage(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        if data[0] == 0xFF && data[1] == 0xD8 { return true }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        if data.starts(with: Data("GIF8".utf8)) { return true }
        return data.starts(with: Data("RIFF".utf8)) && data.subdata(in: 8..<12) == Data("WEBP".utf8)
    }

    private static func decrypt(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count % 16 == 0 else { return nil }
        var out = Data(count: data.count)
        var outLen = 0
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(0),
                    key, kCCKeySizeAES128,
                    iv,
                    inPtr.baseAddress, data.count,
                    outPtr.baseAddress, data.count,
                    &outLen
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return unpad(out.prefix(outLen))
    }

    private static func unpad(_ data: Data) -> Data {
        guard let last = data.last else { return data }
        let pad = Int(last)
        guard pad > 0, pad <= 16, data.count >= pad else { return data }
        let tail = data.suffix(pad)
        if tail.allSatisfy({ Int($0) == pad }) { return data.dropLast(pad) }
        return data
    }
}
