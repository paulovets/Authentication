//
//  JWT.swift
//  Authentication
//
//  Created by Yauheni Paulavets on 3.10.22.
//

import Foundation

public enum LoginProvider: String {
    
    case apple = "SignInWithApple"
    
    case facebook = "Facebook"
}

public struct Jwt: Decodable {
    
    let audience: String?
    
    let cognitoUsername: String?
    
    let email: String?
    
    let expiration: Int64
    
    let firstName: String?
    
    let middleName: String?
    
    let lastName: String?
    
    let loginProvider: LoginProvider?
    
    let personId: String?
    
    let sub: String?
    
    enum CodingKeys: String, CodingKey {
        
        case audience = "aud"
        
        // For Sign in with Apple Cognito maps user's name in different fields
        case appleIDFirstName = "custom:first_name"
        
        case appleIDLastName = "custom:last_name"
        
        case cognitoUsername = "cognito:username"
        
        case email
        
        case expiration = "exp"
        
        case firstName = "given_name"
        
        case identities
        
        case middleName = "middle_name"
        
        case name
        
        case lastName = "family_name"
        
        case personId = "custom:person_id"
        
        case sub
    }
    
    enum IdentitiesCodingKeys: String, CodingKey {
        
        case providerType
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.audience = try? container.decode(String.self, forKey: .audience)
        
        self.cognitoUsername = try? container.decode(String.self, forKey: .cognitoUsername)
        
        self.email = try? container.decode(String.self, forKey: .email)
        self.expiration = try container.decode(Int64.self, forKey: .expiration)
        
        if let fullName = try? container.decode(String.self, forKey: .name) {
            let names = fullName.split(separator: " ")
            
            self.firstName = names.first.map { String($0) }
            self.lastName = names.last.map { String($0) }
            self.middleName = names.dropFirst().dropLast().joined(separator: " ")
        } else {
            let cognitoFirstName: String? = try? container.decode(String.self, forKey: .firstName)
            let appleIDFirstName: String? = try? container.decode(String.self, forKey: .appleIDFirstName)
            
            let cognitoLastName: String? = try? container.decode(String.self, forKey: .lastName)
            let appleIDLastName: String? = try? container.decode(String.self, forKey: .appleIDLastName)
            
            self.firstName = cognitoFirstName ?? appleIDFirstName
            self.middleName = try? container.decode(String.self, forKey: .middleName)
            self.lastName = cognitoLastName ?? appleIDLastName
        }
        
        self.personId = try? container.decode(String.self, forKey: .personId)
        
        let identities = try? container.decode([[String: String?]].self, forKey: .identities)
        let identity = identities?.first
        let identityProvider = (identity?[IdentitiesCodingKeys.providerType.rawValue]) ?? ""
        
        self.loginProvider = LoginProvider(rawValue: identityProvider ?? "")
        
        self.sub = try? container.decode(String.self, forKey: .sub)
    }
}

public extension Jwt {
    
    var isAboutToExpire: Bool {
        (expiration.secondsToMilliseconds - Date().millisecondsSince1970).millisecondsToSeconds <= 10
    }
}

extension Date {
    
    var millisecondsSince1970: Int64 {
        Int64(self.timeIntervalSince1970 * 1000)
    }
}

extension BinaryInteger {
    
    var secondsToMilliseconds: Self {
        self * 1000
    }
    
    var millisecondsToSeconds: Self {
        self / 1000
    }
}
