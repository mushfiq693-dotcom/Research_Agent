import Foundation
import Security
import OSLog

public final class KeychainService: @unchecked Sendable {
    public static let shared = KeychainService()
    
    private let serviceName = "com.personalresearchagent.keychain"
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "KeychainService")
    
    public enum Key: String, CaseIterable, Sendable {
        case openRouter = "openrouter_api_key"
        case braveSearch = "brave_search_api_key"
        
        public var displayName: String {
            switch self {
            case .openRouter: return "OpenRouter API Key"
            case .braveSearch: return "Brave Search API Key"
            }
        }
        
        public var envVarName: String {
            switch self {
            case .openRouter: return "OPENROUTER_API_KEY"
            case .braveSearch: return "BRAVE_API_KEY"
            }
        }
    }
    
    public enum KeychainError: LocalizedError, Sendable {
        case itemNotFound
        case duplicateItem
        case unexpectedData
        case unhandledError(status: OSStatus)
        
        public var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "The requested key was not found in the macOS Keychain."
            case .duplicateItem:
                return "A duplicate key already exists in the Keychain."
            case .unexpectedData:
                return "The Keychain returned unexpected or corrupted data."
            case .unhandledError(let status):
                return "Keychain operation failed with OSStatus code: \(status)."
            }
        }
    }
    
    private init() {
        // Automatically check and load from .env file if Keychain is currently empty
        loadFromEnvFileIfAvailable()
    }
    
    // MARK: - Save Key
    public func saveKey(_ key: Key, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteKey(key)
            return
        }
        
        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Update existing
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key.rawValue
            ]
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                logger.error("Failed to update Keychain item for \(key.displayName): \(updateStatus)")
                throw KeychainError.unhandledError(status: updateStatus)
            }
        } else if status != errSecSuccess {
            logger.error("Failed to save Keychain item for \(key.displayName): \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        
        logger.info("Successfully saved key for \(key.displayName) to Keychain.")
    }
    
    // MARK: - Get Key
    public func getKey(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data, let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        
        // Check Environment variables
        if let envVal = ProcessInfo.processInfo.environment[key.envVarName], !envVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let val = envVal.trimmingCharacters(in: .whitespacesAndNewlines)
            try? saveKey(key, value: val) // Auto-persist to Keychain
            return val
        }
        
        // Check local .env file
        if let envVal = readKeyFromEnvFile(key.envVarName), !envVal.isEmpty {
            try? saveKey(key, value: envVal) // Auto-persist to Keychain
            return envVal
        }
        
        return nil
    }
    
    // MARK: - Delete Key
    public func deleteKey(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete Keychain item for \(key.displayName): \(status)")
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Auto-Load from .env
    public func loadFromEnvFileIfAvailable() {
        for key in Key.allCases {
            if let val = readKeyFromEnvFile(key.envVarName), !val.isEmpty {
                try? saveKey(key, value: val)
            }
        }
    }
    
    private func readKeyFromEnvFile(_ varName: String) -> String? {
        let possiblePaths = [
            FileManager.default.currentDirectoryPath + "/.env",
            FileManager.default.homeDirectoryForCurrentUser.path + "/.env",
            FileManager.default.homeDirectoryForCurrentUser.path + "/Documents/Personal Research Agent/.env"
        ]
        
        for path in possiblePaths {
            guard FileManager.default.fileExists(atPath: path),
                  let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                continue
            }
            
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), trimmed.contains("=") else { continue }
                
                let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0) }
                if parts.count == 2 {
                    let k = parts[0].trimmingCharacters(in: .whitespaces)
                    var v = parts[1].trimmingCharacters(in: .whitespaces)
                    
                    // Remove quotes if present
                    if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
                        v = String(v.dropFirst().dropLast())
                    }
                    
                    if k == varName && !v.isEmpty {
                        return v
                    }
                }
            }
        }
        return nil
    }
    
    // MARK: - Redaction Utility
    public static func redact(_ secret: String) -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else {
            return "******"
        }
        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(4)
        return "\(prefix)...\(suffix)"
    }
}
