#define CAPTURE_EXPERIMENT_LIBRARY
#include "main.mm"
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <cmath>

static NSDictionary *SampleMetrics(CVPixelBufferRef buffer) {
    CVPixelBufferLockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
    size_t w=CVPixelBufferGetWidth(buffer),h=CVPixelBufferGetHeight(buffer),stride=CVPixelBufferGetBytesPerRow(buffer);
    const uint8_t *p=(const uint8_t *)CVPixelBufferGetBaseAddress(buffer);
    const double colors[4][3]={{.95,.04,.07},{.04,.95,.10},{.05,.12,.95},{1,1,1}};
    int matches=0, flipped=0, markers=0, opaque=0, background=0;
    double sum[4]={0,0,0,0};
    for(int row=0;row<6;row++)for(int col=0;col<8;col++) {
        size_t x=(col+.5)*w/8,y=(row+.5)*h/6;
        const uint8_t *b=p+y*stride+4*x;
        double values[4]={b[2]/255.,b[1]/255.,b[0]/255.,b[3]/255.};
        auto close=[&](const double *expected) { return values[3]>.9 && fabs(values[0]-expected[0])<=.10 && fabs(values[1]-expected[1])<=.10 && fabs(values[2]-expected[2])<=.10; };
        if(close(colors[(row+col)%4]))matches++;
        if(close(colors[(5-row+col)%4]))flipped++;
        const double bg[3]={.05,.08,.12};if(close(bg))background++;
        if(values[3]>.9)opaque++;
        if(values[3]>.9 && ((values[0]>.7 && values[1]<.35 && values[2]<.35)||(values[1]>.7 && values[0]<.35 && values[2]<.35)||(values[2]>.7 && values[0]<.35 && values[1]<.35)))markers++;
        for(int k=0;k<4;k++)sum[k]+=values[k];
    }
    CVPixelBufferUnlockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
    double similarity=MAX(matches,flipped)/48.;
    return @{ @"width":@(w),@"height":@(h),@"samplePoints":@48,@"templateSimilarity":@(similarity),
        @"patternDetected":@(similarity>=.90 && markers/48.>=.65),@"partialOrFullPatternDetected":@(markers>=2 && MAX(matches,flipped)>=2),@"markerSampleFraction":@(markers/48.),
        @"opaqueSampleFraction":@(opaque/48.),@"backgroundSimilarity":@(background/48.),
        @"meanRGBA":@[@(sum[0]/48),@(sum[1]/48),@(sum[2]/48),@(sum[3]/48)] };
}

static void SaveSyntheticROI(CVPixelBufferRef buffer,NSString *path) {
    CVPixelBufferLockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
    size_t w=CVPixelBufferGetWidth(buffer),h=CVPixelBufferGetHeight(buffer);
    CGColorSpaceRef cs=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context=CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer),w,h,8,CVPixelBufferGetBytesPerRow(buffer),cs,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    if(context) {
        CGImageRef full=CGBitmapContextCreateImage(context);
        CGImageRef roi=CGImageCreateWithImageInRect(full,CGRectMake(w*.125,h/6.,w*.75,h*2./3.));
        NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithCGImage:roi];
        [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
        CGImageRelease(roi);CGImageRelease(full);CGContextRelease(context);
    }
    CVPixelBufferUnlockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
}

@interface StreamExperiment : NSObject <NSApplicationDelegate,SCStreamOutput,SCStreamDelegate>
@property(nonatomic,strong) FixturePanel *panel;
@property(nonatomic,strong) SCWindow *ownWindow;
@property(nonatomic,strong) SCStream *stream;
@property(nonatomic,strong) NSMutableArray *results;
@property(nonatomic,strong) NSMutableDictionary *phase;
@property(nonatomic,strong) NSString *output;
@property(nonatomic) NSInteger index;
@property(nonatomic) CFTimeInterval changedAt;
@property(nonatomic) BOOL collecting;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL permission;
@property(nonatomic) NSUInteger settledImages;
@property(nonatomic) NSUInteger settledComplete;
@property(nonatomic) NSUInteger phaseGeneration;
- (void)advance;
- (void)findOwnWindow:(NSInteger)attempt;
- (void)finish;
@end
@implementation StreamExperiment {
    std::unique_ptr<CaptureSPI> spi;
    dispatch_source_t animation;
}
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.results=[NSMutableArray array];self.index=-1;spi=std::make_unique<CaptureSPI>();
    self.permission=CGPreflightScreenCaptureAccess();
    if(!self.permission || !spi->available()){[self finish];return;}
    self.panel=[[FixturePanel alloc] initWithContentRect:NSMakeRect(30,30,480,300) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.releasedWhenClosed=NO;self.panel.level=NSFloatingWindowLevel;self.panel.canBecomeVisibleWithoutLogin=NO;
    self.panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary;
    self.panel.hasShadow=NO;self.panel.hidesOnDeactivate=NO;self.panel.sharingType=NSWindowSharingReadOnly;
    self.panel.title=@"Synthetic pixel experiment";
    self.panel.contentView=[[PatternView alloc] initWithFrame:NSMakeRect(0,0,480,300)];
    NSRect frame=NSScreen.mainScreen.visibleFrame;[self.panel setFrameOrigin:NSMakePoint(frame.origin.x+30,NSMaxY(frame)-330)];
    [self.panel orderFrontRegardless];[self.panel displayIfNeeded];spi->apply(self.panel,false);
    animation=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(animation,dispatch_time(DISPATCH_TIME_NOW,0),100*NSEC_PER_MSEC,5*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(animation,^{PatternView *v=(PatternView *)self.panel.contentView;v.tick++;v.needsDisplay=YES;});dispatch_resume(animation);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,90*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!self.finished){[self.results addObject:@{@"status":@"global-timeout"}];[self finish];}});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1000*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self findOwnWindow:0];});
}
- (void)findOwnWindow:(NSInteger)attempt {
    if(self.finished)return;
    if(!CGPreflightScreenCaptureAccess()){[self.results addObject:@{@"status":@"permission-unavailable-no-prompt"}];[self finish];return;}
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content,NSError *error){dispatch_async(dispatch_get_main_queue(),^{
        if(self.finished)return;
        for(SCWindow *w in content.windows)if(w.windowID==(CGWindowID)self.panel.windowNumber){self.ownWindow=w;break;}
        if(!self.ownWindow||error){
            if(attempt<5){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self findOwnWindow:attempt+1];});return;}
            [self.results addObject:@{@"status":@"own-window-unavailable",@"visible":@(self.panel.visible),@"onActiveSpace":@(self.panel.onActiveSpace),@"attempts":@(attempt+1),@"error":error.localizedDescription?:@"No matching own window"}];[self finish];return;
        }
        [self advance];
    });}];
}
- (SCStreamConfiguration *)configuration {
    SCStreamConfiguration *c=[SCStreamConfiguration new];c.width=(size_t)self.panel.frame.size.width;c.height=(size_t)self.panel.frame.size.height;
    c.minimumFrameInterval=CMTimeMake(1,10);c.queueDepth=3;c.pixelFormat=kCVPixelFormatType_32BGRA;
    c.showsCursor=NO;c.capturesAudio=NO;c.colorSpaceName=kCGColorSpaceSRGB;return c;
}
- (void)advance {
    if(self.finished)return;self.collecting=NO;self.index++;
    NSArray *names=@[@"baseline-before-stream",@"background-control",@"baseline-restored-active",@"sharing-none-active",@"sharing-off-active",@"spi-only-active",@"spi-off-active",@"spi-on-before-resize-active",@"spi-only-resized-active",@"spi-resize-reapply-after-settle-active",@"spi-off-resized-active",@"sharing-none-before-stream",@"baseline-new-stream",@"spi-only-before-stream",@"spi-off-new-stream"];
    if(self.index>=(NSInteger)names.count){[self finish];return;}
    NSInteger i=self.index;BOOL restart=(i==0||i>=11);BOOL none=(i==3||i==11);BOOL excluded=(i==5||i==7||i==8||i==9||i==13);
    self.phase=[@{@"name":names[i],@"mechanism":none?@"sharingType.none":excluded?@"CGSSetWindowCaptureExcludeShape":@"none",
        @"transition":restart?@"before-new-stream":@"during-active-stream",@"sharingNone":@(none),@"frames":[NSMutableArray array],@"statusCounts":[NSMutableDictionary dictionary],
        @"settlingDelayMs":@600,@"targetSettledImageFrames":@6,@"phaseTimeoutMs":@3000,@"backgroundControl":@(i==1),
        @"applicationExclusionFilter":@NO,@"pidExclusionFilter":@NO,@"otherWindowExclusionFilter":@NO} mutableCopy];
    void (^configure)(void)=^{
        if(self.finished)return;
        PatternView *v=(PatternView *)self.panel.contentView;v.backgroundOnly=(i==1);
        self.changedAt=CACurrentMediaTime();
        self.panel.sharingType=none?NSWindowSharingNone:NSWindowSharingReadOnly;
        if(i==8)[self.panel setFrame:NSMakeRect(self.panel.frame.origin.x,self.panel.frame.origin.y,640,400) display:YES];
        self.phase[@"api"]=spi->apply(self.panel,excluded);
        if(![self.phase[@"api"][@"cgError"] isEqual:@0]) {self.phase[@"status"]=@"API-error-not-pixel-proof";[self.results addObject:self.phase];[self finish];return;}
        v.needsDisplay=YES;[self.panel displayIfNeeded];
        self.phase[@"localWindowVisible"]=@(self.panel.visible);self.phase[@"onActiveSpace"]=@(self.panel.onActiveSpace);self.phase[@"windowFramePoints"]=NSStringFromRect(self.panel.frame);
        self.phase[@"backingScaleFactor"]=@(self.panel.backingScaleFactor);self.phase[@"requestedPixelSize"]=@[@((NSInteger)self.panel.frame.size.width),@((NSInteger)self.panel.frame.size.height)];
        NSBitmapImageRep *own=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:own];
        self.phase[@"internalRenderControl"]=PixelMetrics(own.CGImage);
        if(restart) {
            SCContentFilter *filter=[[SCContentFilter alloc] initWithDesktopIndependentWindow:self.ownWindow];
            self.stream=[[SCStream alloc] initWithFilter:filter configuration:[self configuration] delegate:self];
            NSError *error=nil;[self.stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_get_main_queue() error:&error];
            if(error){self.phase[@"status"]=@"output-error";self.phase[@"error"]=error.localizedDescription;[self.results addObject:self.phase];[self finish];return;}
            [self.stream startCaptureWithCompletionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
                if(error){self.phase[@"status"]=@"start-error";self.phase[@"error"]=error.localizedDescription;[self.results addObject:self.phase];[self finish];return;}
                [self beginCollection];
            });}];
        } else if(i==8) {
            [self.stream updateConfiguration:[self configuration] completionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
                if(error)self.phase[@"configurationError"]=error.localizedDescription;
                [self beginCollection];
            });}];
        } else [self beginCollection];
    };
    if(restart && self.stream) {
        [self.stream stopCaptureWithCompletionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(error){self.phase[@"status"]=@"stop-error";self.phase[@"error"]=error.localizedDescription;[self.results addObject:self.phase];[self finish];return;}self.stream=nil;configure();});}];
    } else configure();
}
- (void)beginCollection {
    if(self.finished)return;self.phase[@"collectionStartedAfterMutationMs"]=@((CACurrentMediaTime()-self.changedAt)*1000);self.collecting=YES;self.settledImages=0;self.settledComplete=0;NSUInteger generation=++self.phaseGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3000*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(!self.finished && self.collecting && generation==self.phaseGeneration)[self completePhase];
    });
}
- (void)completePhase {
    if(!self.collecting||self.finished)return;self.collecting=NO;
    self.phase[@"settledImageFrames"]=@(self.settledImages);self.phase[@"settledCompleteFrames"]=@(self.settledComplete);
    self.phase[@"status"]=self.settledComplete>=6?@"measured-complete-frames":self.settledImages>=6?@"measured-buffers-not-all-complete":@"insufficient-settled-image-frames";
    self.phase[@"elapsedMs"]=@((CACurrentMediaTime()-self.changedAt)*1000);
    [self.results addObject:self.phase];[self advance];
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if(self.finished||!self.collecting||stream!=self.stream||type!=SCStreamOutputTypeScreen)return;
    NSArray *attachments=(__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample,false);
    NSNumber *status=attachments.firstObject[SCStreamFrameInfoStatus];
    NSString *key=status.stringValue?:@"unknown";NSMutableDictionary *counts=self.phase[@"statusCounts"];counts[key]=@([counts[key] integerValue]+1);
    CVPixelBufferRef buffer=CMSampleBufferGetImageBuffer(sample);double elapsed=(CACurrentMediaTime()-self.changedAt)*1000;
    if(!buffer || !CMSampleBufferIsValid(sample))return;
    // Only the own synthetic window is in this stream. Image memory is released by the callback.
    NSMutableDictionary *frame=[SampleMetrics(buffer) mutableCopy];frame[@"elapsedMs"]=@(elapsed);frame[@"frameStatus"]=status?:@(-1);frame[@"settled"]=@(elapsed>=600);
    NSMutableArray *frames=self.phase[@"frames"];if(frames.count<40)[frames addObject:frame];
    if(elapsed>=600) {
        self.settledImages++;if(status && status.integerValue==SCFrameStatusComplete)self.settledComplete++;
        if(self.settledImages==1)SaveSyntheticROI(buffer,[self.output stringByAppendingPathComponent:[self.phase[@"name"] stringByAppendingString:@"-roi.png"]]);
        if(self.settledImages>=6)[self completePhase];
    }
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    if(self.finished)return;
    [self.results addObject:@{@"status":@"stream-error",@"error":error.localizedDescription}];[self finish];
}
- (void)finish {
    if(self.finished)return;self.finished=YES;self.collecting=NO;
    if(animation)dispatch_source_cancel(animation);
    [self.panel orderOut:nil];NSDictionary *cleanup=spi?spi->apply(self.panel,false):@{};[self.panel close];
    NSDictionary *report=@{@"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"architecture":@"arm64",
        @"method":@"ScreenCaptureKit SCStream desktopIndependentWindow",@"selection":@"own NSWindow window-ID only; no PID/app inclusion or exclusion filter",
        @"existingPermission":@(self.permission),@"permissionRequested":@NO,@"fullDisplayCapture":@NO,@"audioCapture":@NO,@"cursorCapture":@NO,
        @"fullDisplayStatus":@"NOT TESTED: cannot guarantee a private-pixel-free display on the current user desktop",
        @"config":@{@"pixelFormat":@"32BGRA",@"minimumFrameInterval":@"1/10 s",@"queueDepth":@3,@"showsCursor":@NO,@"capturesAudio":@NO,@"colorSpace":@"sRGB"},
        @"threshold":@{@"templateSamples":@48,@"RGBTolerance":@.10,@"minimumTemplateSimilarity":@.90,@"minimumMarkerFraction":@.65,@"partialLeakThreshold":@"at least 2 colored marker samples and 2 matching template samples out of 48",@"settleMs":@600,@"targetSettledFrames":@6,@"timeoutMsPerPhase":@3000},
        @"results":self.results,@"cleanup":cleanup,@"createdRegions":@(spi?spi->created:0),@"releasedRegions":@(spi?spi->released:0)};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[self.output stringByAppendingPathComponent:@"report.json"] atomically:YES];
    void(^done)(void)=^{printf("%s\n",[[self.output stringByAppendingPathComponent:@"report.json"] UTF8String]);[NSApp terminate:nil];};
    if(self.stream)[self.stream stopCaptureWithCompletionHandler:^(NSError *error){if(error)fprintf(stderr,"Cleanup stop: %s\n",error.localizedDescription.UTF8String);dispatch_async(dispatch_get_main_queue(),done);}];else done();
}
@end

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc!=2){fprintf(stderr,"Usage: capture-shape-stream OUTPUT\n");return 2;}
        NSApplication *app=NSApplication.sharedApplication;StreamExperiment *delegate=[StreamExperiment new];
        delegate.output=[NSString stringWithUTF8String:argv[1]];[[NSFileManager defaultManager] createDirectoryAtPath:delegate.output withIntermediateDirectories:YES attributes:nil error:nil];
        app.delegate=delegate;[app run];
    }
}
