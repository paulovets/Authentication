//
//  Error.swift
//  Authentication
//
//  Created by Yauheni Paulavets on 3.10.22.
//

import Foundation
import Shared

enum AuthenticationError: Int, DomainError {
    
    case failed
    
    var identifier: Int {
        self.rawValue
    }
    
    var errorCode: String {
        "\(self.rawValue)"
    }
    
    var details: [String : Any]? {
        nil
    }

    var localizedDescription: String {
        switch self {
        case .failed:
          return "failed"
        }
    }
}
