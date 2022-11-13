//
//  CognitoAuthencticationServiceImpl.swift
//  Authentication
//
//  Created by Yauheni Paulavets on 3.10.22.
//

import Foundation
import AWSMobileClientXCF
import RxSwift
import RxCocoa
import Persistent
import Shared

public final class RxAWSMobileClient: RxAuthenticationSerivce {
    
    public weak var listener: AuthenticationSerivceListener?
    
    private let keychainService: KeychainService
    
    // If we have basic credentials - means it isn't a social sign in
    private var isSocialSignIn: Bool {
        if(_isSocialSignIn == nil) {
            let credentials: Credentials? = self.keychainService.get()
            _isSocialSignIn = credentials == nil
        }
        
        return _isSocialSignIn!
    }

    private var _isSocialSignIn: Bool? = nil
    
    private let awsMobileClientStream: ReplaySubject<AWSMobileClient> = .create(bufferSize: 1)
    
    private var awsMobileClient: Single<AWSMobileClient> {
        awsMobileClientStream
            .take(1)
            .asSingle()
    }
    
    private var awsMobileClientWaitLoginInProgress: Single<AWSMobileClient> {
        Observable.combineLatest(awsMobileClientStream,
                                 loginInProgressStream.filter { !$0 })
            .take(1)
            .asSingle()
            .map { $0.0 }
    }
    
    private var socialSignInTokenStream = ReplaySubject<LoadingState<JWTCredentials>>.create(bufferSize: 1)
    
    private var socialSignInTokenPromise: Single<Result<String?>> {
        socialSignInTokenStream
            .map { loadingState -> Result<String?>? in
                if case let .data(credentials) = loadingState {
                    return .data(credentials.token)
                }
                
                return nil
            }
            .filterNil()
            .take(1)
            .asSingle()
    }
    
    private let loginInProgressStream = BehaviorSubject<Bool>.init(value: false)
    
    private let appleIdentityProvider = "SignInWithApple"
    
    private let facebookIdentityProvider = "Facebook"
    
    private let scopes = ["openid"]
    
    private let bag = DisposeBag()
    
    init(keychainService: KeychainService,
         listener: AuthenticationSerivceListener) {
         self.keychainService = keychainService
         self.listener = listener
        
        listener.configuration
            .map { $0 as? CognitoConfiguration }
            .filterNil()
            .flatMap { [unowned self] in
                self.buildAWSMobileClient($0)
            }
            .filterNil()
            // Current version doesn't allow to reinitialize AWSMobileClient
            .take(1)
            .asSingle()
            .subscribe(onSuccess: { [unowned self] in
                self.awsMobileClientStream.onNext($0)
            })
            .disposed(by: bag)
    }
    
    private func buildAWSMobileClient(_ configuration: CognitoConfiguration) -> Single<AWSMobileClient?> {
        let configuration: [String: Any] = [
            "IdentityManager": [
                "Default": [:]
            ],
            "CognitoUserPool": [
                "Default": [
                    "PoolId": configuration.cognitoPoolId,
                    "AppClientId": configuration.iosClientId,
                    "Region": configuration.cognitoRegion,
                    "MigrationEnabled": true
                ]
            ],
            "Auth": [
                "Default": [
                    "OAuth": [
                        "WebDomain": configuration.webDomain,
                        "AppClientId": configuration.iosClientId,
                        "SignInRedirectURI": configuration.callbackURL,
                        "SignOutRedirectURI": configuration.callbackURL,
                        "Scopes": scopes
                    ]
                ]
            ]
        ]

        let awsMobileClient = AWSMobileClient(configuration: configuration)
        
        let signOutStream = PublishSubject<()>()
        
        awsMobileClient.addUserStateListener(self) { state, _ in
            switch state {
            case .signedOutFederatedTokensInvalid,
                 .signedOutUserPoolsTokenInvalid:
                signOutStream.onNext(())
            default:
                break
            }
        }
            
        signOutStream
            .withLatestFrom(loginInProgressStream) { ($0, $1) }
            .filter { !$0.1 }
            .map { $0.0 }
            .flatMapLatest { [unowned self] _ -> Completable in
                // If we have credentials - means it isn't social sign in
                guard let credentials: Credentials = self.keychainService.get() else {
                    return self.deleteAuthentication()
                              // We don't emit errors from delete
                              .observe(on: MainScheduler.asyncInstance)
                              .do(onCompleted: {
                                  self.listener?.logout()
                              })
                }
                
                self.loginInProgressStream.onNext(true)
                
                return self.login(credentials)
                    .observe(on: MainScheduler.asyncInstance)
                    .do(onError: { _ in
                        self.loginInProgressStream.onNext(false)
                        
                        self.listener?.logout()
                    }, onCompleted: {
                        self.loginInProgressStream.onNext(false)
                    })
            }
            .subscribe()
            .disposed(by: bag)
        
        return Single.create { observer in
            awsMobileClient.initialize { _, _ in
                observer(.success(awsMobileClient))
            }

            return Disposables.create {}
        }
    }
    
    public func appleLogin() -> Completable {
        deleteAuthentication()
            .andThen(socialSignIn(identityProvider: appleIdentityProvider))
            .observe(on: MainScheduler.asyncInstance)
    }

    public func facebookLogin() -> Completable {
        deleteAuthentication()
            .andThen(socialSignIn(identityProvider: facebookIdentityProvider))
            .observe(on: MainScheduler.asyncInstance)
    }
    
    public func login(_ credentials: Credentials) -> Completable {
        deleteAuthentication()
            .andThen(signIn(credentials))
            .observe(on: MainScheduler.asyncInstance)
    }
    
    private func signIn(_ credentials: Credentials) -> Completable {
        awsMobileClient
            .observe(on: MainScheduler.asyncInstance)
            .flatMapCompletable { [unowned self] awsMobileClient in
                return Completable.create { observer -> Disposable in
                    awsMobileClient.signIn(username: credentials.username,
                                           password: credentials.password) { signInResult, error in
                        if signInResult?.signInState == .signedIn {
                            self.update(credentials)
                            
                            observer(.completed)
                            
                            return
                        }
                        
                        observer(.error(AuthenticationError.failed))
                    }
                    
                    return Disposables.create()
                }
            }
    }
    
    private func socialSignIn(identityProvider: String) -> Completable {
        awsMobileClient
            .observe(on: MainScheduler.asyncInstance)
            .flatMapCompletable { [unowned self] awsMobileClient in
                return Completable.create { observer -> Disposable in
                    guard let window: UIWindow = UIApplication.shared.windows.filter({ $0.isKeyWindow }).first else {
                        observer(.error(AuthenticationError.failed))
                        
                        return Disposables.create()
                    }
                    
                    let hostedUIOptions: HostedUIOptions = HostedUIOptions(scopes: self.scopes,
                                                                           identityProvider: identityProvider,
                                                                           // Important to avoid warning alert
                                                                           // https://github.com/aws-amplify/aws-sdk-ios/issues/3141#issuecomment-774176632
                                                                           // https://github.com/aws-amplify/amplify-swift/issues/745#issuecomment-774162694
                                                                           signInPrivateSession: true)
                    
                    awsMobileClient.showSignIn(presentationAnchor: window,
                                               hostedUIOptions: hostedUIOptions) { signInResult, error in
                        if signInResult == .signedIn {
                            observer(.completed)
                            
                            return
                        }
                        
                        observer(.error(AuthenticationError.failed))
                    }
                    
                    return Disposables.create()
                }
            }
    }
    
    private func update(_ credentials: Credentials) {
        keychainService.set(credentials)
    }
    
    public func getToken() -> Single<Result<String?>> {
        isSocialSignIn ? getSocialBasedToken() : getCredentialBasedToken()
    }
    
    private func getCredentialBasedToken() -> Single<Result<String?>> {
        awsMobileClientWaitLoginInProgress
            .flatMap { [unowned self] (awsMobileClient: AWSMobileClient) in
                self.getTokenUtility(awsMobileClient)
            }
            // We are obtaining a token
            // SDK gets a refresh token is expired and emits to signOut stream
            // which in it's turn emits to loginInProgress stream
            // getTokenUtility receives an error - retry once after a short delay
            .retry(maxAttempts: 2, delay: 100)
    }
    
    private func getSocialBasedToken() -> Single<Result<String?>> {
        guard let loadingState = socialSignInTokenStream.value() else {
            socialSignInTokenStream.onNext(.loading)
            
            return getCredentialBasedToken()
        }
        
        switch loadingState {
        case .data(let credentials) where credentials.jwtDomain()?.isAboutToExpire == false:
            return Single.just(.data(credentials.token))
        case .data:
            socialSignInTokenStream.onNext(.loading)
            
            return getCredentialBasedToken()
        case .loading:
            return socialSignInTokenPromise
        case .error:
            return Single.just(.error(AuthenticationError.failed))
        }
    }
    
    private func getTokenUtility(_ awsMobileClient: AWSMobileClient) -> Single<Result<String?>> {
        Single.create { [unowned self] observer in
            awsMobileClient.getTokens { tokens, error in
                guard let jwtCredentials = tokens?.domain() else {
                    observer(.failure(AuthenticationError.failed))

                    return
                }

                switch jwtCredentials.domain() {
                case .error(let error):
                    observer(.failure(error))
                case .data(let authToken):
                    // Store for the social sign in use case
                    // for runtime session only
                    if isSocialSignIn {
                        self.socialSignInTokenStream.onNext(.data(jwtCredentials))
                    }

                    observer(.success(Result.data(authToken)))
                }
            }
            
            return Disposables.create {}
        }
    }
    
    public func deleteAuthentication() -> Completable {
        awsMobileClient
            .flatMapCompletable { [unowned self] in
                self.deleteAuthenticationUtility($0)
            }
            .observe(on: MainScheduler.asyncInstance)
    }

    private func deleteAuthenticationUtility(_ awsMobileClient: AWSMobileClient) -> Completable {
        Completable.create { [unowned self] observer in
            self._isSocialSignIn = nil
            
            self.socialSignInTokenStream = ReplaySubject<LoadingState<JWTCredentials>>.create(bufferSize: 1)
            
            self.keychainService.delete(Credentials.self)
            
            if awsMobileClient.isSignedIn {
                // To use private session feature - it should be log out without parameters
                awsMobileClient.signOut() { _ in
                    observer(.completed)
                }
            } else {
                observer(.completed)
            }

            return Disposables.create {}
        }
    }
    
    public func onFailedRequest() {
        socialSignInTokenStream = ReplaySubject<LoadingState<JWTCredentials>>.create(bufferSize: 1)
    }
}
    
extension RxAWSMobileClient {
    
    public func application(_ app: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?) {
    }
    
    public func application(_ app: UIApplication, open url: URL, options: Dictionary<UIApplication.OpenURLOptionsKey, Any>) -> Bool {
        false
    }
}

private extension Tokens {
    
    func domain() -> JWTCredentials? {
        guard let accessToken = accessToken?.tokenString,
            let idToken = idToken?.tokenString else {
            return nil
        }
        
        return JWTCredentials(accessToken: accessToken,
                              idToken: idToken)
    }
}
