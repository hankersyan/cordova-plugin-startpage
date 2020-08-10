#import "StartPagePlugin.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import "MainViewController.h"
#import "XMLParser.h"
#import <WebKit/WebKit.h>

/// NSUserDefaults
#define kStartPage @"StartPage"
#define kContentSrc @"widget.content.src"

/// config.xml
#define kIncludeVersionInStartPageUrl @"IncludeVersionInStartPageUrl"

/// keys for version in startPage Url (query param):
#define kNativeVersion @"nativeVersion"
#define kNativeBuild @"nativeBuild"

BOOL shouldAddVersionToUrl = NO;
CDVViewController *cdvViewController = nil;

NSString* addVersionToUrlIfRequired(NSString* page) {
    if(shouldAddVersionToUrl) {
        NSString *queryParamPrefix =
        ([page containsString:@"="] && [page containsString:@"?"])?
        @"&":@"?";

        NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];

        NSString *CFBundleShortVersionString = [bundleInfo objectForKey:@"CFBundleShortVersionString"];
        NSString *CFBundleVersion = [bundleInfo objectForKey:(NSString *)kCFBundleVersionKey];

        page = [NSString stringWithFormat:@"%@%@%@=%@&%@=%@",
                page, queryParamPrefix, kNativeVersion, CFBundleShortVersionString, kNativeBuild, CFBundleVersion];
    }
    return page;
}

@implementation StartPagePlugin

- (void)pluginInitialize {

}

/// Note(alonam):
/// -------------
/// We use this tricky way of loading the url because the "page" string param
/// may either represent an html that is part of this bundle, or a remote url with http://balbal/something.html
/// cordova already knows how to load it smartly, using the function CDVViewController.appUrl,
/// however, it's a private function of cordova, so we do this trick:
- (void)loadPageSmartly:(NSString*)page {
    // Because it's a private function in cordova, we invoke it this way:
    cdvViewController.startPage = page;
    NSURL* url = [cdvViewController performSelector:@selector(appUrl)];
    #if WK_WEB_VIEW_ONLY
        [(WKWebView*)self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    #else
        [(UIWebView*)self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    #endif

}

#pragma mark -
#pragma mark Cordova Commmands

- (void)setStartPageUrl:(CDVInvokedUrlCommand *)command {

    NSString *startPageUrl = [command.arguments objectAtIndex:0];
    NSLog(@"********** doing setStartPageUrl %@", startPageUrl);
    if(startPageUrl) {
        NSLog(@"********** 1");
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:startPageUrl forKey:kStartPage];
        [defaults synchronize];

        [self.commandDelegate sendPluginResult: [CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId: command.callbackId];
    } else {
        NSLog(@"********** 2");
        [self.commandDelegate sendPluginResult: [CDVPluginResult
                                                 resultWithStatus: CDVCommandStatus_ERROR
                                                 messageAsString:  @"bad_url"]
                                    callbackId: command.callbackId];
    }
}

- (void)loadStartPage:(CDVInvokedUrlCommand *)command {

    NSString *startPage = addVersionToUrlIfRequired([[NSUserDefaults standardUserDefaults] objectForKey:kStartPage]);
    [self loadPageSmartly:startPage];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];

    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)loadContentSrc:(CDVInvokedUrlCommand *)command {

    NSString *contentSrc = addVersionToUrlIfRequired([[NSUserDefaults standardUserDefaults] objectForKey:kContentSrc]);
    [self loadPageSmartly:contentSrc];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];

    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)resetStartPageToContentSrc:(CDVInvokedUrlCommand *)command {

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[[NSUserDefaults standardUserDefaults] objectForKey:kContentSrc] forKey:kStartPage];
    [defaults synchronize];

    [self.commandDelegate sendPluginResult: [CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId: command.callbackId];
}

@end

#pragma mark -
#pragma mark StartPage Setter Category

@implementation CDVAppDelegate (New)
    
+ (NSURL *)applicationLibraryDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] lastObject];
}

- (void)bootstrap {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // parse config.xml
    NSString *configXmlPath = [[NSBundle mainBundle] pathForResource:@"config" ofType:@"xml"];
    NSString *configXml = [NSString stringWithContentsOfFile:configXmlPath encoding:NSUTF8StringEncoding error:nil];
    NSError *error = nil;
    NSDictionary *dict = [XMLParser dictionaryForXMLString:configXml error:&error];
    NSDictionary *widgetRoot = [dict objectForKey:@"widget"];

    // parse widget.content.src
    NSString *contentSrc = [[widgetRoot objectForKey:@"content"] objectForKey:@"src"];

    // read old widget.content.src
    NSString *oldContentSrc = [defaults objectForKey:kContentSrc];

    NSString *launchUrl = [defaults objectForKey:kStartPage];
    BOOL isDir = NO;
    BOOL isFileExists = [[NSFileManager defaultManager] fileExistsAtPath:launchUrl isDirectory:&isDir];
    
    if ([launchUrl hasPrefix:@"file:///"] && !isFileExists) {
        NSURL* libDir = [CDVAppDelegate applicationLibraryDirectory];
        launchUrl = [NSString stringWithFormat:@"%@files/live-upgrade/www/index.html", libDir.absoluteString];
        isFileExists = [[NSFileManager defaultManager] fileExistsAtPath:launchUrl isDirectory:&isDir] ||
        ([[NSFileManager defaultManager] fileExistsAtPath:[launchUrl stringByReplacingOccurrencesOfString:@"file:///" withString:@"/"] isDirectory:&isDir]);
        
        NSError *error;
        if (isFileExists) {
            NSString *fileContents = [NSString stringWithContentsOfFile:[launchUrl stringByReplacingOccurrencesOfString:@"file:///" withString:@"/"] encoding:NSUTF8StringEncoding error:&error];
            if (error)
                NSLog(@"Error reading file: %@ at %@", error.localizedDescription, launchUrl);

            NSRange rg2 = [fileContents rangeOfString:@"cordova.js"];
            NSRange rg1 = [fileContents rangeOfString:@"src=" options:NSBackwardsSearch range:NSMakeRange(0, rg2.location)];
            NSString* cdvJs = [fileContents substringWithRange:NSMakeRange(rg1.location+4, rg2.location+rg2.length-rg1.location-4)];
            NSLog(@"invoke cordova.js at %@", cdvJs);
            BOOL isJsExists = [[NSFileManager defaultManager] fileExistsAtPath:cdvJs isDirectory:&isDir] ||
            ([[NSFileManager defaultManager] fileExistsAtPath:[cdvJs stringByReplacingOccurrencesOfString:@"file:///" withString:@"/"] isDirectory:&isDir]);
            if (!isJsExists) {
                NSString* appDir = [[NSBundle mainBundle] resourcePath];
                NSString* newCdvJS = [NSString stringWithFormat:@"%@/www/cordova.js", appDir];
                if ([newCdvJS hasPrefix:@"/"] && ![newCdvJS hasPrefix:@"file:///"]) {
                    newCdvJS = [NSString stringWithFormat:@"file://%@", newCdvJS];
                }
                isJsExists = [[NSFileManager defaultManager] fileExistsAtPath:newCdvJS isDirectory:&isDir] ||
                ([[NSFileManager defaultManager] fileExistsAtPath:[newCdvJS stringByReplacingOccurrencesOfString:@"file:///" withString:@"/"] isDirectory:&isDir]);
                NSLog(@"%@ %d", newCdvJS, isJsExists);
                if (isJsExists) {
                    NSString* newFileContents = [fileContents stringByReplacingOccurrencesOfString:cdvJs withString:newCdvJS];
                    [newFileContents writeToFile:[launchUrl stringByReplacingOccurrencesOfString:@"file:///" withString:@"/"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
                }
            }
        }
    }
    
    if (launchUrl && !isFileExists) {
        NSLog(@"launchUrl NOT exists %@, APP bundlePath=%@", launchUrl, [[NSBundle mainBundle] bundlePath]);
#ifdef DEBUG2222
        [[[UIAlertView alloc] initWithTitle:nil
                                    message:[NSString stringWithFormat:@"%@ NOT exists", launchUrl]
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
#endif
    }
    
    if(([contentSrc isEqual:oldContentSrc] && isFileExists) || [launchUrl hasPrefix:@"http"]) {
        self.viewController.startPage = launchUrl;
    } else {
        self.viewController.startPage = contentSrc;
        [defaults setObject:contentSrc forKey:kStartPage];
        [defaults setObject:contentSrc forKey:kContentSrc];
        [defaults synchronize];
    }

    // Check if we need to include version in the url as query params, read from config.xml
    NSArray *preferences = [widgetRoot objectForKey:@"preference"];
    NSUInteger preferencesCount = [preferences count];
    shouldAddVersionToUrl = NO;
    for (NSUInteger i=0; i<preferencesCount; i++) {
        NSDictionary *pref = [preferences objectAtIndex:i];
        if([[pref objectForKey:@"name"] isEqual:kIncludeVersionInStartPageUrl]) {
            NSString *value = [pref objectForKey:@"value"];
            if([value isEqualToString:@"true"]) {
                shouldAddVersionToUrl = YES;
            }
        }
    }

    self.viewController.startPage = addVersionToUrlIfRequired(self.viewController.startPage);
    cdvViewController = self.viewController;
}

- (BOOL)newApplication:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    [self bootstrap];
    BOOL retVal = [self newApplication:application didFinishLaunchingWithOptions:launchOptions];
    return retVal;
}

+ (void)load {
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(application:didFinishLaunchingWithOptions:)), class_getInstanceMethod(self, @selector(newApplication:didFinishLaunchingWithOptions:)));
}

@end
