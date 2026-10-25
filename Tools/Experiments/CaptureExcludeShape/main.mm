// Experimental executable only. Never linked into Copilote or its installable candidate.
// ABI evidence: Chromium 994837a8c8401ca28c6979ced8dd64cc97ca9b92.
#import <AppKit/AppKit.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <memory>

struct CaptureSPI {
    using MainConnection = uint32_t (*)(void);
    using SetShape = CGError (*)(uint32_t, NSInteger, CFTypeRef);
    using CreateRegion = CFTypeRef (*)(CGRect);
    void *handle = nullptr;
    MainConnection connection = nullptr;
    SetShape set = nullptr;
    CreateRegion create = nullptr;
    int created = 0, released = 0, calls = 0;
    explicit CaptureSPI(bool missing = false) {
        handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) return;
        connection = reinterpret_cast<MainConnection>(dlsym(handle, "CGSMainConnectionID"));
        create = reinterpret_cast<CreateRegion>(dlsym(handle, "CGRegionCreateWithRect"));
        set = reinterpret_cast<SetShape>(dlsym(handle, missing ? "CopiloteDeliberatelyMissingSPI" : "CGSSetWindowCaptureExcludeShape"));
    }
    ~CaptureSPI() { if (handle) dlclose(handle); }
    bool available() const { return connection && set && create; }
    NSDictionary *apply(NSWindow *window, bool exclude, bool injectedError = false) {
        NSCAssert(NSThread.isMainThread, @"Main-thread window operations only");
        if (!available()) return @{ @"status": @"unavailable", @"setterCalled": @NO };
        if (!window || ![NSApp.windows containsObject:window] || window.windowNumber <= 0) return @{ @"status": @"invalid-own-window", @"setterCalled": @NO };
        CGRect rect = window.frame; rect.origin = CGPointZero;
        if (rect.size.width <= 0 || rect.size.height <= 0) return @{ @"status": @"invalid-size", @"setterCalled": @NO };
        CFTypeRef region = nullptr;
        if (exclude) {
            region = create(rect);
            if (!region) return @{ @"status": @"region-creation-failed", @"setterCalled": @NO };
            ++created;
        }
        // Fault injection never sends an invalid ID or a cross-process window to WindowServer.
        CGError error = injectedError ? kCGErrorFailure : set(connection(), window.windowNumber, region);
        if (!injectedError) ++calls;
        if (region) { CFRelease(region); ++released; }
        return @{ @"status": error == kCGErrorSuccess ? @"call-succeeded-not-proof-of-exclusion" : @"call-failed",
                  @"cgError": @(error), @"setterCalled": @(!injectedError), @"injectedError": @(injectedError),
                  @"excludeRequested": @(exclude), @"nullRegion": @(!exclude), @"regionOrigin": @[@0,@0],
                  @"regionSizePoints": @[@(rect.size.width),@(rect.size.height)], @"ownWindowID": @(window.windowNumber) };
    }
};

@interface PatternView : NSView
@property(nonatomic) BOOL backgroundOnly;
@property(nonatomic) NSInteger tick;
@end
@implementation PatternView
- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithSRGBRed:0.05 green:0.08 blue:0.12 alpha:1] setFill]; NSRectFill(self.bounds);
    if(self.backgroundOnly){[(self.tick%2 ? NSColor.whiteColor : NSColor.grayColor) setFill];NSRectFill(NSMakeRect(0,0,12,12));return;}
    NSArray<NSColor *> *colors = @[[NSColor colorWithSRGBRed:0.95 green:0.04 blue:0.07 alpha:1],
        [NSColor colorWithSRGBRed:0.04 green:0.95 blue:0.10 alpha:1],
        [NSColor colorWithSRGBRed:0.05 green:0.12 blue:0.95 alpha:1], NSColor.whiteColor];
    for (int row=0; row<6; ++row) for (int col=0; col<8; ++col) {
        [colors[(row+col)%4] setFill];
        NSRectFill(NSMakeRect(col*self.bounds.size.width/8, row*self.bounds.size.height/6,
                            self.bounds.size.width/8, self.bounds.size.height/6));
    }
    [(self.tick%2 ? NSColor.whiteColor : NSColor.grayColor) setFill]; NSRectFill(NSMakeRect(0,0,12,12));
}
@end
@interface FixturePanel : NSPanel @end
@implementation FixturePanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

static NSDictionary *PixelMetrics(CGImageRef image) {
    const size_t width=CGImageGetWidth(image), height=CGImageGetHeight(image);
    NSMutableData *pixels=[NSMutableData dataWithLength:width*height*4];
    CGColorSpaceRef cs=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context=CGBitmapContextCreate(pixels.mutableBytes,width,height,8,width*4,cs,kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!context) return @{ @"metricsUnavailable": @YES };
    CGContextDrawImage(context, CGRectMake(0,0,width,height), image); CGContextRelease(context);
    const uint8_t *b=(const uint8_t *)pixels.bytes; size_t markers=0, opaque=0;
    for(size_t i=0;i<width*height;i++) {
        int r=b[4*i],g=b[4*i+1],blue=b[4*i+2],a=b[4*i+3];
        if(a>230) ++opaque;
        if(a>230 && ((r>180 && g<90 && blue<90)||(g>180 && r<90 && blue<90)||(blue>180 && r<90 && g<90))) ++markers;
    }
    return @{ @"width":@(width), @"height":@(height), @"markerPixels":@(markers),
              @"markerFraction":@((double)markers/(width*height)), @"opaqueFraction":@((double)opaque/(width*height)),
              @"syntheticPatternVisible":@(markers>100) };
}

@interface Experiment : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) FixturePanel *panel;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *observations;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *checks;
@property(nonatomic,strong) NSString *output;
@property(nonatomic,strong) SCWindow *knownOwnWindow;
@property(nonatomic) BOOL presentationAuthorized;
@property(nonatomic) BOOL permission;
@property(nonatomic) BOOL captureRequested;
@property(nonatomic) BOOL finished;
- (void)step:(NSInteger)index;
@end
@implementation Experiment {
    std::unique_ptr<CaptureSPI> spi;
}
- (void)record:(NSString *)name passed:(BOOL)passed { [self.checks addObject:@{ @"name":name,@"passed":@(passed) }]; }
- (void)makePanel {
    self.panel=[[FixturePanel alloc] initWithContentRect:NSMakeRect(0,0,480,300) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.releasedWhenClosed=NO; self.panel.level=NSFloatingWindowLevel; self.panel.canBecomeVisibleWithoutLogin=NO;
    self.panel.hidesOnDeactivate=NO; self.panel.restorable=NO; self.panel.hasShadow=NO;
    self.panel.title=@"Synthetic capture exclusion experiment";
    self.panel.contentView=[[PatternView alloc] initWithFrame:NSMakeRect(0,0,480,300)];
    NSRect screen=NSScreen.mainScreen.visibleFrame;
    [self.panel setFrameOrigin:NSMakePoint(NSMinX(screen)+30,NSMaxY(screen)-330)];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.observations=[NSMutableArray array]; self.checks=[NSMutableArray array];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    spi=std::make_unique<CaptureSPI>();
    CaptureSPI missing(true);
    [self record:@"missing symbol is optional and never invoked" passed:!missing.available() && ![missing.apply(nil,true)[@"setterCalled"] boolValue]];
    [self makePanel]; self.presentationAuthorized=YES;
    [self record:@"fixture window is registered in this process" passed:[NSApp.windows containsObject:self.panel]];
    self.permission=CGPreflightScreenCaptureAccess(); // Never request or change system permissions.
    [self record:@"all three SPI symbols resolved" passed:spi->available()];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(!self.finished) { [self record:@"experiment finished before timeout" passed:NO]; [self finish]; }
    });
    [self step:0];
}
- (void)presentIfAuthorized {
    if (self.presentationAuthorized) [self.panel orderFrontRegardless];
}
- (void)step:(NSInteger)index {
    if (self.finished) return;
    NSArray<NSString *> *names=@[@"baseline-public-readOnly-null-shape",@"public-none-null-shape",@"spi-only-readOnly",@"combined-none-spi",@"resized-combined",@"off-clears-region",@"suspend",@"explicit-resume",@"injected-error",@"off-after-error",@"new-window-combined"];
    if(index >= (NSInteger)names.count) { [self finish]; return; }
    [self.panel orderOut:nil];
    BOOL exclude=(index==2||index==3||index==4||index==7||index==8||index==10);
    BOOL useNone=(index==1||index==3||index==4||index==7||index==8||index==10);
    if(index==4) [self.panel setFrame:NSMakeRect(self.panel.frame.origin.x,self.panel.frame.origin.y,640,400) display:NO];
    if(index==10) {
        NSInteger old=self.panel.windowNumber;
        spi->apply(self.panel,false); [self.panel close]; self.knownOwnWindow=nil;
        [self makePanel]; [self record:@"recreated window receives a new own-window ID" passed:self.panel.windowNumber!=old];
    }
    self.panel.sharingType=useNone?NSWindowSharingNone:NSWindowSharingReadOnly;
    NSMutableDictionary *row=[@{ @"stage":names[index], @"sharingNone":@(useNone) } mutableCopy];
    if(index==6) {
        self.presentationAuthorized=NO;
        [self presentIfAuthorized];
        row[@"visible"]=@(self.panel.visible); row[@"captureStatus"]=@"not-captured-while-suspended";
        [self record:@"suspend hides and revokes automatic presentation" passed:!self.panel.visible];
        [self.observations addObject:row]; [self step:index+1]; return;
    }
    if(index==7) self.presentationAuthorized=YES;
    NSDictionary *api=spi->apply(self.panel,exclude,index==8); row[@"api"]=api;
    BOOL ok=[api[@"cgError"] isEqual:@0];
    // Fail closed in the experimental path; do not silently display after missing/error SPI.
    if(ok) [self presentIfAuthorized];
    row[@"visible"]=@(self.panel.visible);
    if(index==8) {
        [self record:@"nonzero error keeps experimental window hidden" passed:!self.panel.visible];
        row[@"captureStatus"]=@"not-captured-after-injected-error";
        [self.observations addObject:row]; [self step:index+1]; return;
    }
    if(!ok) {
        row[@"captureStatus"]=@"not-captured-unavailable-or-failed";
        [self.observations addObject:row]; [self step:index+1]; return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self.finished)return;
        // Internal render is only a content/control check, never evidence of capture exclusion.
        if(index==0) {
            NSView *view=self.panel.contentView;
            NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
            [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[self.output stringByAppendingPathComponent:@"internal-pattern.png"] atomically:YES];
        }
        if(!self.captureRequested || !self.permission) {
            row[@"captureStatus"]=!self.captureRequested?@"not-requested":@"not-tested-existing-permission-unavailable";
            [self.observations addObject:row]; [self step:index+1]; return;
        }
        [self capture:row completion:^{ [self step:index+1]; }];
    });
}
- (void)capture:(NSMutableDictionary *)row completion:(void (^)(void))completion {
    // Enumeration metadata is immediately filtered; no other application/window is recorded.
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(self.finished)return;
            SCWindow *own=nil;
            for(SCWindow *window in content.windows) {
                if(window.windowID==(CGWindowID)self.panel.windowNumber) { own=window; break; }
            }
            row[@"ownWindowEnumerated"]=@(own!=nil);
            if(own)self.knownOwnWindow=own;
            if(!own)own=self.knownOwnWindow;
            if(!own || error) {
                row[@"captureStatus"]=@"not-tested-own-window-unavailable";
                if(error)row[@"error"]=error.localizedDescription;
                [self.observations addObject:row];completion();return;
            }
            // Absolute boundary: ONLY desktopIndependentWindow, verified app-created window ID.
            if(own.windowID!=(CGWindowID)self.panel.windowNumber) {
                row[@"captureStatus"]=@"refused-foreign-window";[self.observations addObject:row];completion();return;
            }
            SCContentFilter *filter=[[SCContentFilter alloc] initWithDesktopIndependentWindow:own];
            SCStreamConfiguration *config=[SCStreamConfiguration new];
            config.width=(size_t)self.panel.frame.size.width;config.height=(size_t)self.panel.frame.size.height;
            config.showsCursor=NO;config.capturesAudio=NO;
            [SCScreenshotManager captureImageWithFilter:filter configuration:config completionHandler:^(CGImageRef image,NSError *captureError){
                if(image)CGImageRetain(image);
                dispatch_async(dispatch_get_main_queue(),^{
                    if(self.finished){if(image)CGImageRelease(image);return;}
                    if(image) {
                        row[@"captureStatus"]=@"captured-own-synthetic-window";row[@"pixels"]=PixelMetrics(image);
                        NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithCGImage:image];
                        NSString *name=[row[@"stage"] stringByAppendingString:@".png"];
                        [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[self.output stringByAppendingPathComponent:name] atomically:YES];
                        CGImageRelease(image);
                    } else { row[@"captureStatus"]=@"capture-error-not-proof-of-exclusion";row[@"error"]=captureError.localizedDescription?:@"No image"; }
                    [self.observations addObject:row];completion();
                });
            }];
        });
    }];
}
- (void)finish {
    if(self.finished)return;self.finished=YES;self.presentationAuthorized=NO;
    [self.panel orderOut:nil];NSDictionary *cleanup=spi->apply(self.panel,false);[self.panel close];
    [self record:@"every created CF region released" passed:spi->created==spi->released];
    [self record:@"cleanup clears shape or reports unavailable" passed:[cleanup[@"cgError"] isEqual:@0]||!spi->available()];
    NSDictionary *report=@{ @"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"architecture":@"arm64",
        @"captureRequested":@(self.captureRequested),@"existingScreenPermission":@(self.permission),@"permissionRequested":@NO,
        @"captureScope":@"SCScreenshotManager desktopIndependentWindow of own synthetic panel only; no desktop, audio or user app capture",
        @"spiAvailable":@(spi->available()),@"createdRegions":@(spi->created),@"releasedRegions":@(spi->released),@"setterCalls":@(spi->calls),
        @"checks":self.checks,@"observations":self.observations,@"cleanup":cleanup,
        @"receiverTests":@"NOT TESTED",@"hardwareLockSleepMultipleDisplays":@"NOT TESTED",@"cursorInOtherTools":@"NOT TESTED; showsCursor=NO applies only to this harness" };
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    [data writeToFile:[self.output stringByAppendingPathComponent:@"report.json"] atomically:YES];
    printf("%s\n",[[self.output stringByAppendingPathComponent:@"report.json"] UTF8String]);
    [NSApp terminate:nil];
}
@end

#ifndef CAPTURE_EXPERIMENT_LIBRARY
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc<2) { fprintf(stderr,"Usage: capture-shape-experiment OUTPUT [--capture-own-window]\n");return 2; }
        NSApplication *app=NSApplication.sharedApplication;
        Experiment *delegate=[Experiment new];delegate.output=[NSString stringWithUTF8String:argv[1]];
        delegate.captureRequested=argc>2 && strcmp(argv[2],"--capture-own-window")==0;
        [[NSFileManager defaultManager] createDirectoryAtPath:delegate.output withIntermediateDirectories:YES attributes:nil error:nil];
        app.delegate=delegate;[app run];
    }
}

#endif
