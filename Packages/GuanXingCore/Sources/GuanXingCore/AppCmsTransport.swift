import Foundation
import CryptoKit
#if canImport(CommonCrypto)
import CommonCrypto
#endif

// MARK: - 传输层

extension AppCmsSpider {
    struct TransportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func call(path: String, body: String) async throws -> [String: Any] {
        let urlString = config.root + "/api.php" + path
        var headers: [String: String] = [
            "User-Agent": config.userAgent?.isEmpty == false ? config.userAgent! : "okhttp/3.14.9",
            "Content-Type": "application/x-www-form-urlencoded",
            "Connection": "Keep-Alive",
            "app-ui-mode": "light",
            "app-api-verify-time": String(Int(Date().timeIntervalSince1970))
        ]
        if let deviceID = config.deviceID, !deviceID.isEmpty {
            headers["app-user-device-id"] = deviceID
        }
        if let version = config.version, !version.isEmpty {
            headers["app-version-code"] = version
        }
        if let token = config.token, !token.isEmpty {
            headers["app-user-token"] = token
        }

        let text = try await post(urlString, body: body, headers: headers)
        guard let envelope = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw TransportError(message: "返回内容不是 JSON")
        }
        guard let payload = envelope["data"] as? String else {
            // 服务端有时直接返回明文对象
            return envelope
        }
        let plain = try AppCmsCrypto.aesDecrypt(payload, key: config.dataKey, iv: config.dataIv)
        guard let object = try? JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any] else {
            throw TransportError(message: "解密后的内容不是 JSON")
        }
        return object
    }

    func post(_ urlString: String, body: String, headers: [String: String]) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw GuanXingError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = Data(body.utf8)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw GuanXingError.http(http.statusCode)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw TransportError(message: "返回内容不是文本")
            }
            return text
        } catch let error as GuanXingError {
            throw error
        } catch {
            throw GuanXingError.network(error.localizedDescription)
        }
    }

    func jsonBody(_ object: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

// MARK: - 加解密

public enum AppCmsCrypto {
    public static func aesDecrypt(_ base64: String, key: String, iv: String) throws -> String {
        guard let payload = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            throw AppCmsSpider.TransportError(message: "密文不是 Base64")
        }
        let keyData = Data(key.utf8)
        let ivData = Data(iv.utf8)
        guard keyData.count == 16 || keyData.count == 24 || keyData.count == 32, ivData.count == 16 else {
            throw AppCmsSpider.TransportError(message: "密钥长度不合法")
        }
        let blockSize = 16
        var output = Data(count: payload.count + blockSize)
        var written = 0
        let status = output.withUnsafeMutableBytes { outBytes -> CCCryptorStatus in
            guard let outBase = outBytes.baseAddress else { return CCCryptorStatus(kCCMemoryFailure) }
            return payload.withUnsafeBytes { inBytes in
                keyData.withUnsafeBytes { keyBytes in
                    ivData.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyData.count,
                            ivBytes.baseAddress,
                            inBytes.baseAddress, payload.count,
                            outBase, output.count,
                            &written
                        )
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else {
            throw AppCmsSpider.TransportError(message: "AES 解密失败")
        }
        output.removeSubrange(written..<output.count)
        guard let text = String(data: output, encoding: .utf8) ?? TextDecoder.decode(output) else {
            throw AppCmsSpider.TransportError(message: "解密结果不是文本")
        }
        return text
    }

    public static func md5Hex(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
