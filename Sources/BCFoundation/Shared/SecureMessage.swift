import Foundation
import CryptoSwift
import URKit

/// Implements IETF ChaCha20-Poly1305 encryption
///
/// https://datatracker.ietf.org/doc/html/rfc8439
public struct SecureMessage: CustomStringConvertible, Equatable {
    public let plaintext: Data
    public let ciphertext: Data
    public let additionalData: Data // Additional authenticated data (AAD) per RFC8439
    public let key: Key
    public let nonce: Nonce
    public let authenticationTag: AuthenticationTag
    
    /// Encrypt.
    public init?(plaintext: Data, additionalData: Data, key: Key, nonce: Nonce) {
        self.plaintext = plaintext
        self.additionalData = additionalData
        self.key = key
        self.nonce = nonce
        guard let (ciphertext, authenticationTag) = try? AEADChaCha20Poly1305.encrypt(plaintext.bytes, key: key.bytes, iv: nonce.bytes, authenticationHeader: additionalData.bytes) else {
            return nil
        }
        self.ciphertext = Data(ciphertext)
        self.authenticationTag = AuthenticationTag(authenticationTag)!
    }
    
    /// Decrypt.
    public init?(ciphertext: Data, additionalData: Data, key: Key, nonce: Nonce, authenticationTag: AuthenticationTag) {
        self.ciphertext = ciphertext
        self.additionalData = additionalData
        self.key = key
        self.nonce = nonce
        self.authenticationTag = authenticationTag
        guard let (plaintext, success) =
                try? AEADChaCha20Poly1305.decrypt(ciphertext.bytes, key: key.bytes, iv: nonce.bytes, authenticationHeader: additionalData.bytes, authenticationTag: authenticationTag.bytes),
                success
        else {
            return nil
        }
        self.plaintext = Data(plaintext)
    }
    
    public var description: String {
        "Encrypted(plaintext: \(plaintext), ciphertext: \(ciphertext.hex), additionalData: \(additionalData.hex), key: \(key), nonce: \(nonce), authenticationTag: \(authenticationTag))"
    }
    
    public struct Key: CustomStringConvertible, Equatable, Hashable {
        public let data: Data
        
        public init?(_ data: Data) {
            guard data.count == 32 else {
                return nil
            }
            self.data = data
        }
        
        public init() {
            self.init(SecureRandomNumberGenerator.shared.data(count: 32))!
        }
        
        public var bytes: [UInt8] {
            data.bytes
        }
        
        public var description: String {
            data.description.flanked("Key(", ")")
        }
    }
    
    public struct Nonce: CustomStringConvertible, Equatable, Hashable {
        public let data: Data
        
        public init?(_ data: Data) {
            guard data.count == 12 else {
                return nil
            }
            self.data = data
        }
        
        public init() {
            self.init(SecureRandomNumberGenerator.shared.data(count: 12))!
        }

        public var bytes: [UInt8] {
            data.bytes
        }
        
        public var description: String {
            data.hex.flanked("Nonce(", ")")
        }
    }
    
    public struct AuthenticationTag: CustomStringConvertible, Equatable, Hashable {
        public let data: Data
        
        public init?(_ data: Data) {
            guard data.count == 16 else {
                return nil
            }
            self.data = data
        }
        
        public init?(_ bytes: [UInt8]) {
            self.init(Data(bytes))
        }
        
        public var bytes: [UInt8] {
            data.bytes
        }
        
        public var description: String {
            data.hex.flanked("AuthenticationTag(", ")")
        }
    }
}

extension SecureMessage {
    public var cbor: CBOR {
        // Rationale for ordering:
        //   Type number first to support progressive decoding,
        //   then fixed-length fields, nonce first because it is shorter,
        //   then additionalData ("header") before ciphertext ("body").

        let type = CBOR.unsignedInt(1)
        let nonce = CBOR.data(self.nonce.data)
        let authenticationTag = CBOR.data(self.authenticationTag.data)
        let additionalData = CBOR.data(self.additionalData)
        let ciphertext = CBOR.data(self.ciphertext)
        
        return CBOR.array([type, nonce, authenticationTag, additionalData, ciphertext])
    }
    
    public var taggedCBOR: CBOR {
        CBOR.tagged(URType.secureMessage.tag, cbor)
    }
    
    public init(cbor: CBOR, key: Key) throws {
        let (nonce, authenticationTag, additionalData, ciphertext) = try Self.decode(cbor: cbor)
        self.init(ciphertext: ciphertext, additionalData: additionalData, key: key, nonce: nonce, authenticationTag: authenticationTag)!
    }
    
    public init(taggedCBOR: CBOR, key: Key) throws {
        guard case let CBOR.tagged(URType.secureMessage.tag, cbor) = taggedCBOR else {
            throw CBORError.invalidTag
        }
        try self.init(cbor: cbor, key: key)
    }
    
    public static func decode(cbor: CBOR) throws -> (nonce: Nonce, authenticationTag: AuthenticationTag, additionalData: Data, ciphertext: Data)
    {
        guard case let CBOR.array(elements) = cbor else {
            // Doesn't contain an array.
            throw CBORError.invalidFormat
        }

        guard elements.count == 5 else {
            // Wrong number of elements
            throw CBORError.invalidFormat
        }
        
        guard
            case let CBOR.unsignedInt(type) = elements[0],
            type == 1
        else {
            throw CBORError.invalidFormat
        }

        guard
            case let CBOR.data(nonceData) = elements[1],
            let nonce = Nonce(nonceData)
        else {
            throw CBORError.invalidFormat
        }

        guard
            case let CBOR.data(authenticationTagData) = elements[2],
            let authenticationTag = AuthenticationTag(authenticationTagData)
        else {
            throw CBORError.invalidFormat
        }
        
        guard
            case let CBOR.data(additionalData) = elements[3]
        else {
            throw CBORError.invalidFormat
        }
        
        guard
            case let CBOR.data(ciphertext) = elements[4]
        else {
            throw CBORError.invalidFormat
        }
        
        return (nonce, authenticationTag, additionalData, ciphertext)
    }
    
    public static func decode(taggedCBOR: CBOR) throws -> (nonce: Nonce, authenticationTag: AuthenticationTag, additionalData: Data, ciphertext: Data) {
        guard case let CBOR.tagged(URType.secureMessage.tag, cbor) = taggedCBOR else {
            throw CBORError.invalidTag
        }
        return try decode(cbor: cbor)
    }
}

extension SecureMessage {
    public var ur: UR {
        return try! UR(type: URType.secureMessage.type, cbor: cbor)
    }
    
    public init(ur: UR, key: Key) throws {
        guard ur.type == URType.secureMessage.type else {
            throw URError.unexpectedType
        }
        let cbor = try CBOR(ur.cbor)
        try self.init(cbor: cbor, key: key)
    }
    
    public static func decode(ur: UR) throws -> (nonce: Nonce, authenticationTag: AuthenticationTag, additionalData: Data, ciphertext: Data) {
        guard ur.type == URType.secureMessage.type else {
            throw URError.unexpectedType
        }
        let cbor = try CBOR(ur.cbor)
        return try Self.decode(cbor: cbor)
    }
}