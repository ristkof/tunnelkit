//
//  Keychain.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 2/12/17.
//  Copyright (c) 2022 Davide De Rosa. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of TunnelKit.
//
//  TunnelKit is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  TunnelKit is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with TunnelKit.  If not, see <http://www.gnu.org/licenses/>.
//
//  This file incorporates work covered by the following copyright and
//  permission notice:
//
//      Copyright (c) 2018-Present Private Internet Access
//
//      Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//      The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation

// Label -> Name
// Description -> Kind
// Service -> Where
// Account -> Account

/// Error raised by `Keychain` methods.
public enum KeychainError: Error {

    /// Unable to add.
    case add
    
    /// Item not found.
    case notFound
    
    /// Operation cancelled or unauthorized.
    case userCancelled
    
//    /// Unexpected item type returned.
//    case typeMismatch
}

/// Wrapper for easy keychain access and modification.
public class Keychain {
    private let accessGroup: String?

    /**
     Creates a keychain.

     - Parameter group: An optional App Group.
     - Precondition: Proper App Group entitlements (if group is non-nil).
     **/
    public init(group: String?) {
        accessGroup = group
    }
    
    // MARK: Password
    
    /**
     Sets a password.

     - Parameter password: The password to set.
     - Parameter username: The username to set the password for.
     - Parameter context: The context.
     - Parameter userDefined: Optional user-defined data.
     - Parameter label: An optional label.
     - Returns: The reference to the password.
     - Throws: `KeychainError.add` if unable to add the password to the keychain.
     **/
    @discardableResult
    public func set(password: String, for username: String, context: String, userDefined: String? = nil, label: String? = nil) throws -> Data {
        do {
            let currentPassword = try self.password(for: username, context: context)
            guard password != currentPassword else {
                return try passwordReference(for: username, context: context)
            }
            removePassword(for: username, context: context)
        } catch let e as KeychainError {

            // rethrow cancelation
            if e == .userCancelled {
                throw e
            }

            // otherwise, no pre-existing password
        }

        var query = [String: Any]()
        setScope(query: &query, context: context, userDefined: userDefined)
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrLabel as String] = label
        query[kSecAttrAccount as String] = username
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = password.data(using: .utf8)
        query[kSecReturnPersistentRef as String] = true

        var ref: CFTypeRef?
        let status = SecItemAdd(query as CFDictionary, &ref)
        guard status == errSecSuccess, let refData = ref as? Data else {
            throw KeychainError.add
        }
        return refData
    }
    
    /**
     Removes a password.

     - Parameter username: The username to remove the password for.
     - Parameter context: The context.
     - Parameter userDefined: Optional user-defined data.
     - Returns: `true` if the password was successfully removed.
     **/
    @discardableResult public func removePassword(for username: String, context: String, userDefined: String? = nil) -> Bool {
        var query = [String: Any]()
        setScope(query: &query, context: context, userDefined: userDefined)
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrAccount as String] = username

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }

    /**
     Gets a password.

     - Parameter username: The username to get the password for.
     - Parameter context: The context.
     - Parameter userDefined: Optional user-defined data.
     - Returns: The password for the input username.
     - Throws: `KeychainError.notFound` if unable to find the password in the keychain.
     **/
    public func password(for username: String, context: String, userDefined: String? = nil) throws -> String {
        var query = [String: Any]()
        setScope(query: &query, context: context, userDefined: userDefined)
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrAccount as String] = username
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            break
            
        case errSecUserCanceled:
            throw KeychainError.userCancelled

        default:
            throw KeychainError.notFound
        }
        guard let data = result as? Data else {
            throw KeychainError.notFound
        }
        guard let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        return password
    }

    /**
     Gets a password reference.

     - Parameter username: The username to get the password for.
     - Parameter context: The context.
     - Parameter userDefined: Optional user-defined data.
     - Returns: The password reference for the input username.
     - Throws: `KeychainError.notFound` if unable to find the password in the keychain.
     **/
    public func passwordReference(for username: String, context: String, userDefined: String? = nil) throws -> Data {
        var query = [String: Any]()
        setScope(query: &query, context: context, userDefined: userDefined)
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrAccount as String] = username
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnPersistentRef as String] = true
        
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            break
            
        case errSecUserCanceled:
            throw KeychainError.userCancelled

        default:
            throw KeychainError.notFound
        }
        guard let data = result as? Data else {
            throw KeychainError.notFound
        }
        return data
    }
    
    /**
     Gets a password associated with a password reference.

     - Parameter reference: The password reference.
     - Returns: The password for the input reference.
     - Throws: `KeychainError.notFound` if unable to find the password in the keychain.
     **/
    public static func password(forReference reference: Data) throws -> String {
        var query = [String: Any]()
        query[kSecValuePersistentRef as String] = reference
        query[kSecReturnData as String] = true
        
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            break
            
        case errSecUserCanceled:
            throw KeychainError.userCancelled

        default:
            throw KeychainError.notFound
        }
        guard let data = result as? Data else {
            throw KeychainError.notFound
        }
        guard let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        return password
    }
    
    // MARK: Key
    
    // https://forums.developer.apple.com/thread/13748
    
    /**
     Adds a public key.

     - Parameter identifier: The unique identifier.
     - Parameter data: The public key data.
     - Returns: The `SecKey` object representing the public key.
     - Throws: `KeychainError.add` if unable to add the public key to the keychain.
     **/
    public func add(publicKeyWithIdentifier identifier: String, data: Data) throws -> SecKey {
        var query = [String: Any]()
        query[kSecClass as String] = kSecClassKey
        query[kSecAttrApplicationTag as String] = identifier
        query[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
        query[kSecAttrKeyClass as String] = kSecAttrKeyClassPublic
        query[kSecValueData as String] = data

        // XXX
        query.removeValue(forKey: kSecAttrService as String)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.add
        }
        return try publicKey(withIdentifier: identifier)
    }
    
    /**
     Gets a public key.

     - Parameter identifier: The unique identifier.
     - Returns: The `SecKey` object representing the public key.
     - Throws: `KeychainError.notFound` if unable to find the public key in the keychain.
     **/
    public func publicKey(withIdentifier identifier: String) throws -> SecKey {
        var query = [String: Any]()
        query[kSecClass as String] = kSecClassKey
        query[kSecAttrApplicationTag as String] = identifier
        query[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
        query[kSecAttrKeyClass as String] = kSecAttrKeyClassPublic
        query[kSecReturnRef as String] = true

        // XXX
        query.removeValue(forKey: kSecAttrService as String)

        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            break
            
        case errSecUserCanceled:
            throw KeychainError.userCancelled

        default:
            throw KeychainError.notFound
        }
//        guard let key = result as? SecKey else {
//            throw KeychainError.typeMismatch
//        }
//        return key
        return result as! SecKey
    }
    
    /**
     Removes a public key.

     - Parameter identifier: The unique identifier.
     - Returns: `true` if the public key was successfully removed.
     **/
    @discardableResult public func remove(publicKeyWithIdentifier identifier: String) -> Bool {
        var query = [String: Any]()
        query[kSecClass as String] = kSecClassKey
        query[kSecAttrApplicationTag as String] = identifier
        query[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
        query[kSecAttrKeyClass as String] = kSecAttrKeyClassPublic

        // XXX
        query.removeValue(forKey: kSecAttrService as String)

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
    
    // MARK: Helpers
    
        public func setScope(query: inout [String: Any], context: String, userDefined: String?) {
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
//            #if os(macOS)
//            if #available(macOS 10.15, *) {
//                query[kSecUseDataProtectionKeychain as String] = true
//            }
//            #endif
        }
        query[kSecAttrService as String] = context
        if let userDefined = userDefined {
            query[kSecAttrGeneric as String] = userDefined
        }
    }
}
