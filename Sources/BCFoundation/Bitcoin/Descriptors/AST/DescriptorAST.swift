//
//  DescriptorAST.swift
//  
//
//  Created by Wolf McNally on 12/4/21.
//

import Foundation
@_exported import URKit

protocol DescriptorAST: CustomStringConvertible {
    func scriptPubKey(chain: Chain?, addressIndex: UInt32?, privateKeyProvider: PrivateKeyProvider?, comboOutput: OutputDescriptor.ComboOutput?) -> ScriptPubKey?
    func hdKey(chain: Chain?, addressIndex: UInt32?, privateKeyProvider: PrivateKeyProvider?, comboOutput: OutputDescriptor.ComboOutput?) -> HDKey?
    var requiresAddressIndex: Bool { get }
    var requiresChain: Bool { get }
    var unparsed: String { get }
    var untaggedCBOR: CBOR { get }
    var taggedCBOR: CBOR { get }

    static func parse(_ parser: DescriptorParser) throws -> DescriptorAST?
}

extension DescriptorAST {
    var requiresAddressIndex: Bool {
        false
    }
    
    var requiresChain: Bool {
        false
    }
    
    var description: String {
        unparsed
    }
}
