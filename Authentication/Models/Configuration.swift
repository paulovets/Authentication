//
//  CognitoConfiguration.swift
//  Authentication
//
//  Created by Yauheni Paulavets on 3.10.22.
//

import Foundation

public protocol Configuration {}

public struct CognitoConfiguration: Configuration, Equatable {
    
    public let callbackURL = "my-app-schema://product.com"
    
    public let cognitoPoolId: String
    
    public let cognitoRegion: String
    
    public let iosClientId: String
    
    public let webDomain: String
    
    public init(appleToCognitoClientId: String,
                cognitoPoolId: String,
                cognitoRegion: String,
                iosClientId: String,
                webDomain: String) {
        self.cognitoPoolId = cognitoPoolId
        self.cognitoRegion = cognitoRegion
        self.iosClientId = iosClientId
        self.webDomain = webDomain
    }
}
