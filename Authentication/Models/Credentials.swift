//
//  Credentials.swift
//  Authentication
//
//  Created by Yauheni Paulavets on 3.10.22.
//

import Foundation
import Persistent
import Shared

public struct Credentials: KeychainItemProtocol {
    
    public static let key = String(describing: Credentials.self)
    
    public var username: String
    
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct JWTCredentials {
    
    public let accessToken: String
    
    public let idToken: String
    
    public init(accessToken: String, idToken: String) {
        self.accessToken = accessToken
        self.idToken = idToken
    }
}

extension JWTCredentials {
    
    var token: String {
        ["Bearer", idToken].joined(separator: "")
    }
    
    func domain() -> Result<String> {
        guard let jwtDto = decodeJWTToken(),
              let _ = jwtDto.personId else {
            return .error(AuthenticationError.failed)
        }
        
        return .data(token)
    }
    
    func jwtDomain() -> Jwt? {
        decodeJWTToken()
    }
}

private extension JWTCredentials {
    
    func decodeJWTToken() -> Jwt? {
        guard let bodyData = idToken.base64Decode() else {
            return nil
        }
        
        return try? JSONDecoder().decode(Jwt.self, from: bodyData)
    }
}

private extension String {
    
    /// More details on this function implementation here: https://github.com/auth0/JWTDecode.swift
    func base64Decode() -> Data? {
        let parts = self.components(separatedBy: ".")
        
        guard parts.count == 3 else {
            return nil
        }
        
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let length = Double(base64.lengthOfBytes(using: String.Encoding.utf8))
        
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = requiredLength - length
        
        if paddingLength > 0 {
            let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
            base64 += padding
        }
        
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }
}
