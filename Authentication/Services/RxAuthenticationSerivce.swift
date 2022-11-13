//
//  AuthenticationService.swift
//  Authentication
//
//  Created by Yauheni Paulavets on 3.10.22.
//

import Foundation
import UIKit
import Shared
import RxSwift

public protocol AuthenticationSerivceListener {
    
    func logout()
}

public protocol RxAuthenticationSerivce {
    
    var listener: AuthenticationSerivceListener { get }
    
    var configurationStream: ReplaySubject<Configuration> { get }
    
    func application(_ app: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?)
    
    func application(_ app: UIApplication, open url: URL, options: Dictionary<UIApplication.OpenURLOptionsKey, Any>) -> Bool
    
    func login(_ credentials: Credentials) -> Completable
    
    func appleLogin() -> Completable
    
    func facebookLogin() -> Completable
    
    func getToken() -> Single<Result<String?>>
    
    func deleteAuthentication() -> Completable
    
    func onFailedRequest()
}
