
//
//  SocialLoginViewController.m
//  cloudmine-ios
//
//  Copyright (c) 2012 CloudMine, LLC. All rights reserved.
//  See LICENSE file included with SDK for details.
//

#import "CMUIViewController+Modal.h"
#import "CMSocialLoginViewController.h"
#import "CMWebService.h"
#import "CMStore.h"
#import "CMUser.h"

@interface CMSocialLoginViewController ()
{
    NSMutableData* responseData;
    UIView* pendingLoginView;
    UIActivityIndicatorView* activityView;
}

@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UINavigationBar *navigationBar;

@end

@implementation CMSocialLoginViewController

- (id)initForService:(NSString *)service appID:(NSString *)appID apiKey:(NSString *)apiKey user:(CMUser *)user params:(NSDictionary *)params {
    
    if ( (self = [super init]) ) {
        _user = user;
        _targetService = service;
        _appID = appID;
        _apiKey = apiKey;
        _params = params;
        _challenge = [[NSUUID UUID] UUIDString];
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _webView = [[UIWebView alloc] initWithFrame:self.view.frame];
    _webView.scalesPageToFit = YES;
    _webView.delegate = self;
    [self.view addSubview:_webView];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation { //deprecated in iOS6
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)viewWillAppear:(BOOL)animated {
    // Clear Cookies
    NSHTTPCookie *cookie;
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (cookie in [storage cookies]) {
        [storage deleteCookie:cookie];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    if (self.isModal)
    {
        self.webView.frame = CGRectMake(0, 44, self.view.frame.size.width, self.view.frame.size.height - 44);
        self.navigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
        UINavigationItem *navigationItem = [[UINavigationItem alloc] initWithTitle:self.targetService];
        navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStyleBordered target:self action:@selector(dismiss)];
        self.navigationBar.items = @[navigationItem];
        
        //
        // Set the tint color of our navigation bar to match the tint of the
        // view controller's navigation bar that is responsible for presenting
        // us modally.
        //
        if ([self.presentingViewController respondsToSelector:@selector(navigationBar)])
        {
            UIColor *presentingTintColor = ((UINavigationController *)self.presentingViewController).navigationBar.tintColor;
            self.navigationBar.tintColor = presentingTintColor;
        }
        [self.view addSubview:self.navigationBar];
    }
    else
    {
        if (self.navigationBar)
        {
            [self.navigationBar removeFromSuperview];
            self.navigationBar = nil;
        }
    }
    
    NSString *urlStr = [NSString stringWithFormat:@"%@/app/%@/account/social/login?service=%@&apikey=%@&challenge=%@",
                        CM_BASE_URL, _appID, _targetService, _apiKey, _challenge];
    
    ///
    /// Link accounts if user is logged in. If you don't want the accounts linked, log out the user.
    ///
    if ( _user && _user.isLoggedIn)
        urlStr = [urlStr stringByAppendingFormat:@"&session_token=%@", _user.token];
    
    ///
    /// Add any additional params to the request
    ///
    if ( _params != nil && [_params count] > 0 ) {
        for (NSString *key in _params) {
            urlStr = [urlStr stringByAppendingFormat:@"&%@=%@", key, [_params valueForKey:key]];
        }
    }
    
#ifdef DEBUG
    NSLog(@"Webview Loading: %@", urlStr);
#endif
    
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]]];
}


#pragma mark - UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView *)webView { }

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    
    NSString *currentURLstr = [[[webView request] URL] absoluteString];
    
    NSString *baseURLstr = [NSString stringWithFormat:@"%@/app/%@/account/social/login/complete", CM_BASE_URL, _appID];
    
    if (currentURLstr.length >= baseURLstr.length) {
        NSString *comparableRequestStr = [currentURLstr substringToIndex:baseURLstr.length];
        
        // If at the challenge complete URL, prepare and send GET request for session token info
        if ([baseURLstr isEqualToString:comparableRequestStr]) {
            
            ///
            /// Probably rebuild all this too
            ///
            
            // Display pending login view during request/processing
            pendingLoginView = [[UIView alloc] initWithFrame:self.webView.bounds];
            pendingLoginView.center = self.webView.center;
            pendingLoginView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.8];
            activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            activityView.frame = CGRectMake(pendingLoginView.frame.size.width / 2, pendingLoginView.frame.size.height / 2, activityView.bounds.size.width, activityView.bounds.size.height);
            activityView.center = self.webView.center;
            [pendingLoginView addSubview:activityView];
            [activityView startAnimating];
            [self.view addSubview:pendingLoginView];
            [self.view bringSubviewToFront:pendingLoginView];
            
            if ([self.delegate respondsToSelector:@selector(cmSocialLoginViewController:completeSocialLoginWithChallenge:)]) {
                [self.delegate cmSocialLoginViewController:self completeSocialLoginWithChallenge:_challenge];
            }
        }
    }
    /// Else, this is an internal page we don't care about
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    /**
     * Interesting enough, this method is called sometimes when authenticating with Facebook - but the page continuous to load, and
     * does so sucessfully. The user can actually login. Other time though, the request may fail and be an actual failure.
     *
     * Because we don't really know the nature of this error, nor can we assume, we need to call the delegate and inform them of the error.
     */
    NSLog(@"WebView error. This sometimes happens when the User is logging into a social network where cookies have been stored and is already logged in. %@", [error description]);
    if ([self.delegate respondsToSelector:@selector(cmSocialLoginViewController:hadError:)]) {
        [self.delegate cmSocialLoginViewController:self hadError:error];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark -

- (void)dismiss {
    /**
     * The User may dismiss the dialog, but we still need to inform the delegate.
     *
     */
    if ([self.delegate respondsToSelector:@selector(cmSocialLoginViewControllerWasDismissed:)]) {
        [self.delegate cmSocialLoginViewControllerWasDismissed:self];
    }
    
    [self dismissModalViewControllerAnimated:YES];
}


@end
