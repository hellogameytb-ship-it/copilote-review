// Separate protocol: preserve the prior single-mechanism harness and reuse its fixture helpers.
#define main PreviousStreamHarnessMain
#include "stream.mm"
#undef main

static double HostSeconds() { return CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())); }
static NSDictionary *CompositeMetrics(CVPixelBufferRef buffer) {
    CVPixelBufferLockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
    size_t w=CVPixelBufferGetWidth(buffer),h=CVPixelBufferGetHeight(buffer),stride=CVPixelBufferGetBytesPerRow(buffer);
    const uint8_t *pixels=(const uint8_t *)CVPixelBufferGetBaseAddress(buffer);
    double error=0;int transparent=0;
    for(int row=0;row<6;row++)for(int col=0;col<8;col++) {
        const uint8_t *b=pixels+(size_t)((row+.5)*h/6)*stride+4*(size_t)((col+.5)*w/8);
        double a=b[3]/255.,rgb[3]={b[2]/255.,b[1]/255.,b[0]/255.};
        double bg[2][3]={{.15,.75,.85},{.85,.25,.65}};
        for(int k=0;k<3;k++)error+=fabs(rgb[k]+bg[(row+col)%2][k]*(1-a)-bg[(row+col)%2][k]);
        if(a<.01)transparent++;
    }
    CVPixelBufferUnlockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
    return @{@"syntheticBackgroundMAE":@(error/(48*3)),@"transparentSampleFraction":@(transparent/48.),@"formula":@"premultiplied source RGB + generated checker RGB * (1-alpha); not a receiver capture"};
}

@interface AddendumExperiment : NSObject <NSApplicationDelegate,NSWindowDelegate,SCStreamOutput,SCStreamDelegate>
@property(nonatomic,strong) FixturePanel *panel;
@property(nonatomic,strong) SCStream *stream;
@property(nonatomic,strong) NSMutableArray *results;
@property(nonatomic,strong) NSArray<NSDictionary *> *scenarios;
@property(nonatomic,strong) NSMutableDictionary *phase;
@property(nonatomic,strong) NSString *output;
@property(nonatomic,strong) NSString *segment;
@property(nonatomic) NSInteger index;
@property(nonatomic) NSInteger mode;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL collecting;
@property(nonatomic) BOOL actionRunning;
@property(nonatomic) BOOL existingPermission;
@property(nonatomic) double startedAt;
@property(nonatomic) double lastCallback;
@property(nonatomic) double motionEndedAt;
@property(nonatomic) double lateApplyAt;
@property(nonatomic) NSPoint baseOrigin;
- (void)nextPhase;
- (void)finish;
@end
@implementation AddendumExperiment {
    std::unique_ptr<CaptureSPI> spi;
    dispatch_source_t animation;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];self.results=[NSMutableArray array];spi=std::make_unique<CaptureSPI>();
    self.existingPermission=CGPreflightScreenCaptureAccess();
    if(!self.existingPermission||!spi->available()){[self finish];return;}
    NSMutableArray *cases=[NSMutableArray array];
    for(NSNumber *width in @[@480,@640])for(NSNumber *mode in @[@0,@1,@2,@3])
        [cases addObject:@{@"name":[NSString stringWithFormat:@"stable-%@-mode%@",width,mode],@"kind":@"stable",@"width":width,@"mode":mode,@"strategy":@"none"}];
    [cases addObject:@{@"name":@"background-control",@"kind":@"background",@"width":@640,@"mode":@0,@"strategy":@"none"}];
    for(NSNumber *mode in @[@0,@1,@2,@3]) {
        NSArray *strategies=mode.integerValue>=2?@[@"didResize",@"seriesEnd"]:@[@"none"];
        for(NSString *strategy in strategies)[cases addObject:@{@"name":[NSString stringWithFormat:@"resize-mode%@-%@",mode,strategy],@"kind":@"resize",@"width":@480,@"mode":mode,@"strategy":strategy}];
    }
    for(NSNumber *mode in @[@1,@2,@3]) [cases addObject:@{@"name":[NSString stringWithFormat:@"move-mode%@",mode],@"kind":@"move",@"width":@640,@"mode":mode,@"strategy":@"none"}];
    [cases addObject:@{@"name":@"final-off-control",@"kind":@"stable",@"width":@640,@"mode":@0,@"strategy":@"none"}];
    self.scenarios=cases;self.index=-1;
    self.panel=[[FixturePanel alloc] initWithContentRect:NSMakeRect(0,0,480,300) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.releasedWhenClosed=NO;self.panel.level=NSFloatingWindowLevel;self.panel.canBecomeVisibleWithoutLogin=NO;
    self.panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary;
    self.panel.hasShadow=NO;self.panel.hidesOnDeactivate=NO;self.panel.sharingType=NSWindowSharingReadOnly;self.panel.delegate=self;
    self.panel.title=@"Synthetic combined-policy experiment";
    self.panel.contentView=[[PatternView alloc] initWithFrame:NSMakeRect(0,0,480,300)];
    NSRect screen=NSScreen.mainScreen.visibleFrame;self.baseOrigin=NSMakePoint(NSMinX(screen)+40,NSMinY(screen)+80);
    [self.panel setFrameOrigin:self.baseOrigin];[self.panel orderFrontRegardless];[self.panel displayIfNeeded];spi->apply(self.panel,false);
    animation=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(animation,dispatch_time(DISPATCH_TIME_NOW,0),NSEC_PER_SEC/30,2*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(animation,^{PatternView *v=(PatternView *)self.panel.contentView;v.tick++;v.needsDisplay=YES;});dispatch_resume(animation);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!self.finished){[self.results addObject:@{@"status":@"global-timeout"}];[self finish];}});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1000*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self findOwnWindow:0];});
}
- (void)findOwnWindow:(NSInteger)attempt {
    if(self.finished)return;
    if(!CGPreflightScreenCaptureAccess()){[self finish];return;}
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content,NSError *error){dispatch_async(dispatch_get_main_queue(),^{
        if(self.finished)return;SCWindow *own=nil;
        for(SCWindow *w in content.windows)if(w.windowID==(CGWindowID)self.panel.windowNumber){own=w;break;}
        if(!own||error){if(attempt<5){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self findOwnWindow:attempt+1];});return;}[self.results addObject:@{@"status":@"own-window-unavailable"}];[self finish];return;}
        SCContentFilter *filter=[[SCContentFilter alloc] initWithDesktopIndependentWindow:own];
        SCStreamConfiguration *config=[SCStreamConfiguration new];config.width=640;config.height=400;config.scalesToFit=YES;config.preservesAspectRatio=YES;
        config.minimumFrameInterval=CMTimeMake(1,30);config.queueDepth=3;config.pixelFormat=kCVPixelFormatType_32BGRA;config.colorSpaceName=kCGColorSpaceSRGB;config.showsCursor=NO;config.capturesAudio=NO;
        self.stream=[[SCStream alloc] initWithFilter:filter configuration:config delegate:self];NSError *e=nil;
        [self.stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_get_main_queue() error:&e];
        if(e){[self.results addObject:@{@"status":@"output-error",@"error":e.localizedDescription}];[self finish];return;}
        [self.stream startCaptureWithCompletionHandler:^(NSError *startError){dispatch_async(dispatch_get_main_queue(),^{
            if(startError){[self.results addObject:@{@"status":@"start-error",@"error":startError.localizedDescription}];[self finish];return;}[self nextPhase];
        });}];
    });}];
}
- (void)logEvent:(NSString *)kind extra:(NSDictionary *)extra {
    if(!self.phase)return;
    NSMutableDictionary *row=[@{@"kind":kind,@"elapsedMs":@((HostSeconds()-self.startedAt)*1000),@"frame":NSStringFromRect(self.panel.frame),@"inLiveResize":@(self.panel.inLiveResize),@"segment":self.segment?:@"setup"} mutableCopy];
    [row addEntriesFromDictionary:extra];[self.phase[@"events"] addObject:row];
}
- (void)apply:(NSString *)reason {
    NSDictionary *api=spi->apply(self.panel,(self.mode&2)!=0);
    [self logEvent:reason extra:@{@"api":api}];
    if(![api[@"cgError"] isEqual:@0]){self.phase[@"status"]=@"API-error";[self.panel orderOut:nil];[self finish];}
}
- (void)nextPhase {
    if(self.finished)return;self.collecting=NO;self.actionRunning=NO;self.index++;
    if(self.index>=(NSInteger)self.scenarios.count){[self finish];return;}
    if(!CGPreflightScreenCaptureAccess()){[self.results addObject:@{@"status":@"permission-unavailable-no-prompt"}];[self finish];return;}
    NSDictionary *scenario=self.scenarios[self.index];self.mode=[scenario[@"mode"] integerValue];self.startedAt=HostSeconds();self.motionEndedAt=0;self.lateApplyAt=0;
    self.segment=@"setup";self.phase=[scenario mutableCopy];self.phase[@"frames"]=[NSMutableArray array];self.phase[@"events"]=[NSMutableArray array];self.phase[@"statusCounts"]=[NSMutableDictionary dictionary];self.phase[@"startedHostSeconds"]=@(self.startedAt);
    self.collecting=YES;
    double width=[scenario[@"width"] doubleValue];[self.panel setFrame:NSMakeRect(self.baseOrigin.x,self.baseOrigin.y,width,width/1.6) display:YES];
    ((PatternView *)self.panel.contentView).backgroundOnly=[scenario[@"kind"] isEqual:@"background"];
    self.panel.sharingType=(self.mode&1)?NSWindowSharingNone:NSWindowSharingReadOnly;[self apply:@"initial-policy"];
    if(self.finished)return;
    self.phase[@"policyAppliedHostSeconds"]=@(HostSeconds());self.phase[@"sharingNone"]=@((self.mode&1)!=0);self.phase[@"spiExclude"]=@((self.mode&2)!=0);
    self.phase[@"visible"]=@(self.panel.visible);self.phase[@"onActiveSpace"]=@(self.panel.onActiveSpace);self.phase[@"backingScale"]=@(self.panel.backingScaleFactor);
    NSView *view=self.panel.contentView;NSBitmapImageRep *bm=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:bm];self.phase[@"internalControl"]=PixelMetrics(bm.CGImage);
    NSInteger expected=self.index;
    // A documented warm reapply ensures comparable geometry at the start of each trajectory.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(self.finished||self.index!=expected)return;[self apply:@"warm-geometry-reapply"];self.segment=@"steady-before";});
    BOOL motion=[scenario[@"kind"] isEqual:@"resize"]||[scenario[@"kind"] isEqual:@"move"];
    if(motion)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(self.finished||self.index!=expected)return;self.segment=@"motion";self.actionRunning=YES;[self motionStep:1 index:expected];});
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(self.finished||self.index!=expected)return;[self completePhase];});
}
- (void)motionStep:(NSInteger)step index:(NSInteger)index {
    if(self.finished||self.index!=index)return;BOOL resize=[self.phase[@"kind"] isEqual:@"resize"];
    if(resize){double width=480+160.*step/12.;[self.panel setFrame:NSMakeRect(self.baseOrigin.x,self.baseOrigin.y,width,width/1.6) display:YES];}
    else [self.panel setFrameOrigin:NSMakePoint(self.baseOrigin.x+step*4,self.baseOrigin.y+step*2)];
    [self logEvent:resize?@"programmatic-resize-step":@"programmatic-move-step" extra:@{@"step":@(step)}];
    if(step<12)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self motionStep:step+1 index:index];});
    else {
        self.actionRunning=NO;self.motionEndedAt=HostSeconds();self.segment=@"after-series";
        [self logEvent:@"synthetic-series-ended-not-native-live-resize-end" extra:@{}];
        if([self.phase[@"strategy"] isEqual:@"seriesEnd"])[self apply:@"end-of-synthetic-series-reapply"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(self.finished||self.index!=index)return;self.segment=@"after-delayed-reapply";[self apply:@"delayed-after-series-reapply"];self.lateApplyAt=HostSeconds();});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(self.finished||self.index!=index)return;[self completePhase];});
    }
}
- (void)windowDidResize:(NSNotification *)n {
    if(n.object!=self.panel)return;[self logEvent:@"native-windowDidResize" extra:@{}];
    if(self.actionRunning&&[self.phase[@"strategy"] isEqual:@"didResize"])[self apply:@"reapply-from-windowDidResize"];
}
- (void)windowDidMove:(NSNotification *)n {if(n.object==self.panel)[self logEvent:@"native-windowDidMove" extra:@{}];}
- (void)windowWillStartLiveResize:(NSNotification *)n {if(n.object==self.panel)[self logEvent:@"native-windowWillStartLiveResize" extra:@{}];}
- (void)windowDidEndLiveResize:(NSNotification *)n {if(n.object==self.panel)[self logEvent:@"native-windowDidEndLiveResize" extra:@{}];}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if(self.finished||!self.collecting||stream!=self.stream||type!=SCStreamOutputTypeScreen)return;
    NSArray *a=(__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample,false);NSDictionary *attachment=a.firstObject;
    NSNumber *status=attachment[SCStreamFrameInfoStatus];NSMutableDictionary *counts=self.phase[@"statusCounts"];NSString *key=status.stringValue?:@"unknown";counts[key]=@([counts[key] integerValue]+1);
    double now=HostSeconds(),elapsed=(now-self.startedAt)*1000;CVPixelBufferRef buffer=CMSampleBufferGetImageBuffer(sample);
    NSMutableDictionary *row=[@{@"elapsedMs":@(elapsed),@"callbackHostSeconds":@(now),@"presentationSeconds":@(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))),@"frameStatus":status?:@(-1),@"segment":self.segment?:@"setup",@"gapSincePreviousCallbackMs":@(self.lastCallback?(now-self.lastCallback)*1000:0),@"framePointsAtCallback":NSStringFromRect(self.panel.frame),@"inLiveResize":@(self.panel.inLiveResize),@"hasImage":@(buffer!=nil)} mutableCopy];self.lastCallback=now;
    if(attachment[SCStreamFrameInfoContentRect])row[@"contentRectMetadata"]=[attachment[SCStreamFrameInfoContentRect] description];
    if(buffer&&CMSampleBufferIsValid(sample)) {
        [row addEntriesFromDictionary:SampleMetrics(buffer)];[row addEntriesFromDictionary:CompositeMetrics(buffer)];
        double pts=[row[@"presentationSeconds"] doubleValue];row[@"ptsMinusPolicyAppliedMs"]=@((pts-[self.phase[@"policyAppliedHostSeconds"] doubleValue])*1000);
        BOOL leak=[row[@"partialOrFullPatternDetected"] boolValue];NSString *roiKey=nil;
        if(elapsed>=800&&[self.segment isEqual:@"steady-before"]&&!self.phase[@"savedSteadyROI"])roiKey=@"steady";
        if(leak&&self.mode!=0&&[self.segment isEqual:@"motion"]&&!self.phase[@"savedLeakROI"])roiKey=@"motion-leak";
        if(self.lateApplyAt&&now-self.lateApplyAt>=.2&&!self.phase[@"savedLateROI"])roiKey=@"after-delayed";
        if(roiKey){NSString *file=[NSString stringWithFormat:@"%@-%@-roi.png",self.phase[@"name"],roiKey];SaveSyntheticROI(buffer,[self.output stringByAppendingPathComponent:file]);self.phase[[roiKey isEqual:@"steady"]?@"savedSteadyROI":[roiKey isEqual:@"motion-leak"]?@"savedLeakROI":@"savedLateROI"]=file;}
    }
    NSMutableArray *frames=self.phase[@"frames"];if(frames.count<180)[frames addObject:row];else self.phase[@"framesTruncated"]=@YES;
}
- (void)completePhase {
    self.collecting=NO;self.phase[@"elapsedMs"]=@((HostSeconds()-self.startedAt)*1000);self.phase[@"status"]=@"completed";
    if(self.motionEndedAt)self.phase[@"seriesEndElapsedMs"]=@((self.motionEndedAt-self.startedAt)*1000);
    if(self.lateApplyAt)self.phase[@"lateApplyElapsedMs"]=@((self.lateApplyAt-self.startedAt)*1000);
    [self.results addObject:self.phase];[self nextPhase];
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {if(!self.finished){[self.results addObject:@{@"status":@"stream-error",@"error":error.localizedDescription}];[self finish];}}
- (void)finish {
    if(self.finished)return;self.finished=YES;self.collecting=NO;if(animation)dispatch_source_cancel(animation);
    [self.panel orderOut:nil];NSDictionary *cleanup=spi?spi->apply(self.panel,false):@{};self.panel.delegate=nil;[self.panel close];
    NSDictionary *report=@{@"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"architecture":@"arm64",@"method":@"SCStream desktopIndependentWindow; only app-created window ID, no PID/app exclusion filter",
        @"config":@{@"width":@640,@"height":@400,@"minimumFrameInterval":@"1/30s",@"scalesToFit":@YES,@"preservesAspectRatio":@YES,@"pixelFormat":@"32BGRA",@"colorSpace":@"sRGB",@"queueDepth":@3,@"showsCursor":@NO,@"capturesAudio":@NO},
        @"existingPermission":@(self.existingPermission),@"permissionRequested":@NO,@"desktopCapture":@NO,@"physicalLiveResize":@"NOT TESTED; programmatic frame trajectory with actual windowDidResize callbacks",
        @"phaseFrameCap":@180,@"resizeSteps":@12,@"stepIntervalMs":@60,@"settleWarmReapplyMs":@600,@"motionStartsMs":@1200,@"lateReapplyAfterSeriesMs":@600,
        @"threshold":@{@"samples":@48,@"RGBTolerance":@.10,@"fullSimilarity":@.90,@"fullMarkerFraction":@.65,@"partial":@"two color markers and two spatial matches"},
        @"results":self.results,@"cleanup":cleanup,@"createdRegions":@(spi?spi->created:0),@"releasedRegions":@(spi?spi->released:0)};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[self.output stringByAppendingPathComponent:@"report.json"] atomically:YES];
    void(^done)(void)=^{printf("%s\n",[[self.output stringByAppendingPathComponent:@"report.json"] UTF8String]);[NSApp terminate:nil];};
    if(self.stream)[self.stream stopCaptureWithCompletionHandler:^(NSError *error){if(error)fprintf(stderr,"Stop: %s\n",error.localizedDescription.UTF8String);dispatch_async(dispatch_get_main_queue(),done);}];else done();
}
@end
int main(int argc,const char *argv[]) {
    @autoreleasepool {if(argc!=2)return 2;NSApplication *app=NSApplication.sharedApplication;AddendumExperiment *d=[AddendumExperiment new];d.output=[NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:d.output withIntermediateDirectories:YES attributes:nil error:nil];app.delegate=d;[app run];}
}
