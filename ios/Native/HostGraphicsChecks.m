#import <TargetConditionals.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIKit.h>
#endif
#include "CoreApi.h"
#include "CoreWorker.h"
#include <stdio.h>
#include <stdlib.h>
#if TARGET_OS_OSX && defined(RYU_GUEST_SMOKE)
#include <sys/mman.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>
static void *guestCode;
static NSString *programPath;
static void begin_write(void) { pthread_jit_write_protect_np(0); }
static void publish_code(void *address, uintptr_t size) {
    sys_icache_invalidate(address, size);
    pthread_jit_write_protect_np(1);
}
#define CHECK_RUNS 1
#else
#define CHECK_RUNS 2
#endif

extern int ryu_create_metal_surface(void *instance, void *layer, uint64_t *surface);
static CAMetalLayer *testLayer;
static NSString *libraryPath;
static NSString *dataPath;
static int testStatus = -1;
static int completedRuns;
#if TARGET_OS_OSX
static NSWindow *testWindow;
#endif

static int never_cancel(void) {
#if !TARGET_OS_OSX
    static int calls;
    if (completedRuns == 0 && ++calls == 10) {
        // Hold a live, already-presented frame while the compositor is sampled.
        // Capturing after Vulkan teardown observes a legitimately cleared layer.
        NSString *ready = [dataPath stringByAppendingPathComponent:@"frame-ready"];
        NSString *captured = [dataPath stringByAppendingPathComponent:@"frame-captured"];
        [@"ready" writeToFile:ready atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:45];
        while (![NSFileManager.defaultManager fileExistsAtPath:captured] && deadline.timeIntervalSinceNow > 0)
            [NSThread sleepForTimeInterval:0.05];
        if (![NSFileManager.defaultManager fileExistsAtPath:captured]) return 1;
    }
#endif
    return 0;
}
static void *check_renderer(void *unused) {
    (void)unused;
    @autoreleasepool {
        char report[4096] = {0};
        for (int run = 0; run < CHECK_RUNS; run++) {
#ifdef RYU_GUEST_SMOKE
            testStatus = ryu_core_homebrew_run(guestCode, guestCode, 256UL * 1024 * 1024,
                begin_write, publish_code, (const uint8_t *)libraryPath.UTF8String,
                (__bridge void *)testLayer, 640, 360, ryu_create_metal_surface, never_cancel,
                (const uint8_t *)programPath.UTF8String, (const uint8_t *)dataPath.UTF8String,
                (uint8_t *)report, sizeof(report));
#else
            testStatus = ryu_core_graphics_check((const uint8_t *)libraryPath.UTF8String,
                (__bridge void *)testLayer, 640, 360, ryu_create_metal_surface, never_cancel,
                (const uint8_t *)dataPath.UTF8String, (uint8_t *)report, sizeof(report));
#endif
            printf("Renderer run %d: %s\n", run + 1, report);
            fflush(stdout);
            if (testStatus != 0) break;
            completedRuns++;
        }
        NSDictionary *result = @{ @"status": @(testStatus), @"runs": @(completedRuns),
            @"report": [NSString stringWithUTF8String:report] ?: @"No report" };
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&error];
        BOOL saved = [json writeToFile:[dataPath stringByAppendingPathComponent:@"graphics-result.json"]
            options:NSDataWritingAtomic error:&error];
        if (!saved) { NSLog(@"Could not save renderer result: %@", error); testStatus = -1; }
    }
    return NULL;
}

static void begin_checks(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int status = ryu_core_on_thread(check_renderer, NULL, RYU_CORE_STACK_SIZE);
        if (status != 0) { fprintf(stderr, "Renderer worker failed: %d\n", status); exit(2); }
        dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_OSX
            [NSApp stop:nil];
            [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
                modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
#else
            // Keep the composed surface available for simctl screenshot validation.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                exit(testStatus == 0 && completedRuns == 2 ? 0 : 1);
            });
#endif
        });
    });
}

static CAMetalLayer *make_layer(void) {
    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = NO;
    layer.drawableSize = CGSizeMake(640, 360);
    return layer;
}

#if TARGET_OS_OSX
int main(int argc, char **argv) {
    @autoreleasepool {
#ifdef RYU_GUEST_SMOKE
        if (argc != 4) return 2;
        programPath = [NSString stringWithUTF8String:argv[3]];
        guestCode = mmap(NULL, 256UL * 1024 * 1024, PROT_READ | PROT_WRITE | PROT_EXEC,
            MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
        if (guestCode == MAP_FAILED) return 3;
#else
        if (argc != 3) return 2;
#endif
        libraryPath = [NSString stringWithUTF8String:argv[1]];
        dataPath = [NSString stringWithUTF8String:argv[2]];
        [NSFileManager.defaultManager createDirectoryAtPath:dataPath withIntermediateDirectories:YES attributes:nil error:NULL];
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        testWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        testLayer = make_layer();
        testWindow.contentView.wantsLayer = YES;
        testWindow.contentView.layer = testLayer;
        [testWindow center];
        [testWindow makeKeyAndOrderFront:nil];
        [NSApp finishLaunching];
        begin_checks();
        [NSApp run];
        [testWindow orderOut:nil];
        return testStatus == 0 && completedRuns == CHECK_RUNS ? 0 : 1;
    }
}
#else
@interface GraphicsSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(strong, nonatomic) UIWindow *window;
@end
@implementation GraphicsSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = controller;
    testLayer = make_layer();
    CGFloat width = MIN(self.window.bounds.size.width - 32, 640);
    testLayer.frame = CGRectMake(16, 120, width, width * 9 / 16);
    testLayer.drawableSize = CGSizeMake(640, 360);
    [controller.view.layer addSublayer:testLayer];
    [self.window makeKeyAndVisible];
    libraryPath = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"MoltenVK.framework/MoltenVK"];
    dataPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ begin_checks(); });
}
@end
@interface GraphicsDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation GraphicsDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)application; (void)options;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"GraphicsChecks" sessionRole:session.role];
    configuration.delegateClass = GraphicsSceneDelegate.class;
    return configuration;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(GraphicsDelegate.class)); }
}
#endif
