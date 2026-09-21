#!/usr/bin/env python3
"""Host integration checks at CADisplayLink factory/FPS entry points.

Reads actual production hook and helper bodies; never reproduces the gate in
Python. Only platform boundaries are fixtures: bundle, display/modes, UIKit
windows, Objective-C associations, original CA setters/factory, clock/scheduler.
Logos %orig and GNU Objective-C dispatch are adapted for the host compiler.

Runs on Linux with clang + GNUstep or macOS with Xcode Foundation. This is not
an iOS/ARC/arm64e test or a frame-time benchmark. Counters are fixture API calls.
"""
from pathlib import Path
import platform
import re
import shlex
import subprocess
import tempfile
import unittest
import json

REPO = Path(__file__).resolve().parents[1]


def read_source(name):
    return (REPO / 'src' / name).read_text()


def body(text, start):
    opening = text.index('{', start)
    depth = 0
    for i in range(opening, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[start:i + 1] + '\n'
    raise ValueError('unclosed source body')


def function(text, name):
    match = re.search(r'^static [^\n]*\b' + re.escape(name) + r'\([^;\n]*\)\s*\{', text, re.M)
    if not match:
        raise ValueError('function not found: ' + name)
    return body(text, match.start())


def hook_method(text, signature, original_call):
    method = body(text, text.index(signature))
    # Preserve the full method body. Only Logos' original-dispatch syntax changes.
    method = re.sub(r'%orig\(([^;]*)\)', lambda m: original_call(m.group(1)), method)
    return method.replace('%orig', original_call(None))


FIXTURE = r'''
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#ifndef __unused
#define __unused __attribute__((unused))
#endif
typedef double CFAbsoluteTime;
typedef double CFTimeInterval;
typedef struct { float minimum, maximum, preferred; } CAFrameRateRange;
typedef int ScopeOnceToken;
static int scheduled;
#define dispatch_after(...) do { scheduled++; } while (0)
#ifndef __APPLE__
// Mirror the public declaration supplied by CoreFoundation on macOS so Linux
// also rejects a fixture accidentally redeclaring this API with static linkage.
extern CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);
#endif
static CFAbsoluteTime ScopeAbsoluteTimeGetCurrent(void) { return 100.0; }
#define CFAbsoluteTimeGetCurrent ScopeAbsoluteTimeGetCurrent

static NSString *fixtureBundle;
static BOOL fixtureVisible;
static int associationSets, associationGets, targetClassReads, factoryCalls;
static int linkReasonWrites, linkRangeWrites, fpsWrites, sourceCreates;
static CAFrameRateRange sourceRange;

@interface ScopeBundle : NSObject
+ (id)mainBundle;
- (NSString *)bundleIdentifier;
@end
@implementation ScopeBundle
+ (id)mainBundle { static id b; if (!b) b=[ScopeBundle new]; return b; }
- (NSString *)bundleIdentifier { return fixtureBundle; }
@end
#define NSBundle ScopeBundle

@interface CADisplay : NSObject
+ (id)mainDisplay;
- (NSArray *)availableModes;
@end
@implementation CADisplay
+ (id)mainDisplay { static id d; if (!d) d=[CADisplay new]; return d; }
- (NSArray *)availableModes { return @[@{@"refreshRate":@120}]; }
@end

@interface UIWindow : NSObject
- (BOOL)hidden;
- (id)rootViewController;
@end
@implementation UIWindow
- (BOOL)hidden { return !fixtureVisible; }
- (id)rootViewController { return nil; }
@end
@interface FVWindow : UIWindow @end
@implementation FVWindow @end
@interface UIApplication : NSObject
+ (id)sharedApplication;
- (NSArray *)windows;
@end
@implementation UIApplication
+ (id)sharedApplication { static id a; if (!a) a=[UIApplication new]; return a; }
- (NSArray *)windows { static id w; if (!w) w=[FVWindow new]; return @[w]; }
@end
@interface UIScrollView : NSObject
- (BOOL)dragging;
- (BOOL)tracking;
- (BOOL)decelerating;
@end
@implementation UIScrollView
- (BOOL)dragging { return NO; }
- (BOOL)tracking { return NO; }
- (BOOL)decelerating { return NO; }
@end

@interface UIViewInProcessAnimationManager : NSObject @end
@implementation UIViewInProcessAnimationManager
- (Class)class { targetClassReads++; return [super class]; }
@end

@interface CADynamicFrameRateSource : NSObject
- (id)initWithDisplay:(id)display;
- (void)setHighFrameRateReason:(unsigned int)r;
- (void)setHighFrameRateReasons:(const unsigned int *)r count:(NSUInteger)n;
- (void)setPreferredFrameRateRange:(CAFrameRateRange)r;
@end
@implementation CADynamicFrameRateSource
- (id)initWithDisplay:(id)display { sourceCreates++; return [super init]; }
- (void)setHighFrameRateReason:(unsigned int)r {}
- (void)setHighFrameRateReasons:(const unsigned int *)r count:(NSUInteger)n {}
- (void)setPreferredFrameRateRange:(CAFrameRateRange)r { sourceRange=r; }
@end

@interface CADisplayLink : NSObject {
@public NSString *storedTargetClass;
@public CAFrameRateRange recordedRange;
@public NSInteger recordedFPS;
}
+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel;
- (void)setPreferredFrameRateRange:(CAFrameRateRange)range;
- (void)setPreferredFramesPerSecond:(NSInteger)fps;
- (void)setHighFrameRateReason:(unsigned int)r;
- (void)setHighFrameRateReasons:(const unsigned int *)r count:(NSUInteger)n;
@end
static CADisplayLink *lastOriginalLink;
static CADisplayLink *ScopeOriginalFactory(id target,SEL sel) {
    factoryCalls++; lastOriginalLink=[[CADisplayLink new] autorelease]; return lastOriginalLink;
}
static void ScopeOriginalRange(CADisplayLink *link,CAFrameRateRange range) { linkRangeWrites++; link->recordedRange=range; }
static void ScopeOriginalFPS(CADisplayLink *link,NSInteger fps) { fpsWrites++; link->recordedFPS=fps; }
static void ScopeAssociationSet(id obj,const void *key,id value,int policy) {
    associationSets++; ((CADisplayLink *)obj)->storedTargetClass=[value copy];
}
static id ScopeAssociationGet(id obj,const void *key) { associationGets++; return ((CADisplayLink *)obj)->storedTargetClass; }
#define objc_setAssociatedObject ScopeAssociationSet
#define objc_getAssociatedObject ScopeAssociationGet
#define OBJC_ASSOCIATION_COPY_NONATOMIC 3
'''

TAIL = r'''
int main(int argc,char **argv) { @autoreleasepool {
    if (argc!=3) return 2;
    NSString *scenario=[NSString stringWithUTF8String:argv[2]];
    BOOL isFloat=[scenario hasPrefix:@"float"];
    BOOL isSB=[scenario hasPrefix:@"sb"];
    fixtureBundle=isSB ? @"com.apple.springboard" : (isFloat ? @"com.be-huge.floating-view" : @"org.telegram.Telegram");
    fixtureVisible=[scenario hasSuffix:@"visible"];
    CADisplayLink *link=nil;
    BOOL factoryMode=strcmp(argv[1],"factory")==0;
    if (factoryMode) {
        id target=[[UIViewInProcessAnimationManager new] autorelease];
        for (int i=0;i<1000;i++) link=[CADisplayLink displayLinkWithTarget:target selector:NULL];
    } else {
        link=[[CADisplayLink new] autorelease];
        // Precondition: existing link created by a Float animation manager.
        // Seed storage without counting an association operation in this seam.
        link->storedTargetClass=@"UIViewInProcessAnimationManager";
        for (int i=0;i<1000;i++) [link setPreferredFramesPerSecond:60];
    }
    NSDictionary *out=@{@"association_sets":@(associationSets),@"association_gets":@(associationGets),
       @"target_class_reads":@(targetClassReads),@"factory_calls":@(factoryCalls),
       @"returned_original_link":@(factoryMode && link==lastOriginalLink),
       @"link_range_writes":@(linkRangeWrites),@"range_min":@(link->recordedRange.minimum),
       @"range_max":@(link->recordedRange.maximum),@"range_preferred":@(link->recordedRange.preferred),
       @"fps_writes":@(fpsWrites),@"last_fps":@(link->recordedFPS),
       @"source_creates":@(sourceCreates),@"source_range_preferred":@(sourceRange.preferred),
       @"scheduled_callbacks":@(scheduled)};
    NSData *data=[NSJSONSerialization dataWithJSONObject:out options:0 error:NULL];
    puts([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] UTF8String]);
} return 0; }
'''


def integration_source():
    utility = read_source('PMUtility.xm.inc')
    keepalive = read_source('PMKeepAlive.xm.inc')
    floating = read_source('PMFloat.xm.inc')
    rendering = read_source('PMRenderingHooks.xm.inc')
    entry = (REPO / 'Tweak.xmi').read_text()
    target_define = re.search(r'^#define TARGET_FPS[^\n]*$', entry, re.M)
    if not target_define:
        raise ValueError('production TARGET_FPS definition not found')
    source = FIXTURE + '\n' + target_define.group(0) + '\n' + utility
    source += keepalive[:keepalive.index('// ═')]
    source += function(keepalive, 'PMGlobalSBApplyForced')
    source += '\nstatic void PMAppEnsurePersistentSource(void);\nstatic void PMAppRefreshPersistentSource(void);\n'
    source += floating[:floating.index('static BOOL PMFloatFeatureEnabled')]
    for name in ['PMFloatFeatureEnabled', 'PMFloatIsArmed', 'PMFloatIsEligibleNow',
                 'PMStringHasFloatingViewMarker', 'PMFloatIsFloatingWindow',
                 'PMFloatAnyFloatingWindowVisible', 'PMFloatApplyDisplayFrameRateSource',
                 'PMFloatPreArm', 'PMFloatDisplayLinkTargetClass',
                 'PMFloatTargetIsInProcessAnimationManager']:
        source += function(floating, name)
    source += read_source('PMAppPersistent.xm.inc')
    source += '\n@implementation CADisplayLink\n'
    source += hook_method(rendering, '+ (CADisplayLink *)displayLinkWithTarget:',
                          lambda _: 'ScopeOriginalFactory(target, sel)')
    source += hook_method(rendering, '- (void)setPreferredFrameRateRange:',
                          lambda value: 'ScopeOriginalRange(self, ' + (value or 'range') + ')')
    source += hook_method(rendering, '- (void)setPreferredFramesPerSecond:',
                          lambda value: 'ScopeOriginalFPS(self, ' + (value or 'fps') + ')')
    source += '''
- (void)setHighFrameRateReason:(unsigned int)r { linkReasonWrites++; }
- (void)setHighFrameRateReasons:(const unsigned int *)r count:(NSUInteger)n { linkReasonWrites++; }
@end
'''
    source += TAIL
    # dispatch_once is a platform boundary: the fixture is single-threaded.
    # Use a fixture token name instead of colliding with Apple's dispatch typedef.
    source = source.replace('static dispatch_once_t onceToken;', 'static ScopeOnceToken onceToken;')
    source = re.sub(r'dispatch_once\(&onceToken,\s*\^\{(.*?)\}\);',
                    r'if (!onceToken) { onceToken=1; \1 }', source, flags=re.S)
    source = re.sub(r'(static SEL \w+ = )nil;', r'\1NULL;', source)
    if platform.system() != 'Darwin':
        # GNU runtime obtains the IMP before the typed call; production Apple
        # objc_msgSend dispatch is otherwise retained, including @catch bodies.
        for cast, receiver, selector in [
            ('PMUIntSetterDyn', 'obj', 'singleSel'),
            ('PMReasonsSetterDyn', 'obj', 'multiSel'),
            ('PMRangeSetterDyn', 'obj', 'sel'),
            ('PMInitFn', 'allocd', 'initS'),
            ('PMInitWithDisplayFn', 'allocated', 'initSel')]:
            source = source.replace('(' + cast + ')objc_msgSend',
                                    '(' + cast + ')objc_msg_lookup(' + receiver + ', ' + selector + ')')
    return source


def compile_fixture(directory):
    source = directory / 'metadata_scope.m'
    binary = directory / 'metadata_scope'
    source.write_text(integration_source())
    checks = ['-std=gnu11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
              '-Wno-unused-function', '-Wno-unused-variable']
    if platform.system() == 'Darwin':
        command = ['xcrun', '--sdk', 'macosx', 'clang', *checks, '-fno-objc-arc', str(source),
                   '-framework', 'Foundation', '-o', str(binary)]
    else:
        flags = shlex.split(subprocess.check_output(['gnustep-config', '--objc-flags'], text=True))
        libraries = shlex.split(subprocess.check_output(['gnustep-config', '--base-libs'], text=True))
        include = subprocess.check_output(['gcc', '-print-file-name=include'], text=True).strip()
        command = ['clang', *flags, *checks, '-I' + include, str(source), '-o', str(binary), *libraries]
    built = subprocess.run(command, cwd=directory, capture_output=True, text=True)
    if built.returncode:
        raise RuntimeError('host fixture compile failed:\n' + built.stdout + built.stderr)
    return binary


class FloatMetadataScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='pm120-metadata-scope-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.binary = compile_fixture(Path(cls.temp.name))

    def observe(self, seam, scenario):
        output = subprocess.check_output([str(self.binary), seam, scenario], text=True, timeout=15)
        return json.loads(output)

    def test_factory_skips_ordinary_app_metadata_but_preserves_120_and_float(self):
        for scenario in ['ordinary', 'float_hidden', 'float_visible', 'sb_hidden', 'sb_visible']:
            with self.subTest(scenario=scenario):
                result = self.observe('factory', scenario)
                float_host = scenario.startswith('float')
                self.assertEqual(result['association_sets'], 1000 if float_host else 0)
                self.assertEqual(result['target_class_reads'], 1000 if float_host else 0)
                self.assertEqual(result['association_gets'], 0)
                self.assertEqual(result['factory_calls'], 1000)
                self.assertTrue(result['returned_original_link'])
                self.assertEqual(result['link_range_writes'], 1000)
                self.assertEqual([result['range_min'], result['range_max'], result['range_preferred']], [120, 120, 120])
                self.assertEqual(result['source_creates'], 1 if scenario == 'float_visible' else 0)
                if scenario == 'float_visible':
                    self.assertEqual(result['source_range_preferred'], 120)

    def test_fps_setter_skips_ordinary_app_metadata_but_preserves_120_and_float(self):
        for scenario in ['ordinary', 'float_hidden', 'float_visible', 'sb_hidden', 'sb_visible']:
            with self.subTest(scenario=scenario):
                result = self.observe('fps', scenario)
                float_host = scenario.startswith('float')
                self.assertEqual(result['association_gets'], 1000 if float_host else 0)
                self.assertEqual(result['association_sets'], 0)
                self.assertEqual(result['target_class_reads'], 0)
                self.assertEqual(result['factory_calls'], 0)
                self.assertEqual(result['fps_writes'], 1000)
                self.assertEqual(result['last_fps'], 120)
                self.assertEqual(result['source_creates'], 1 if scenario == 'float_visible' else 0)
                if scenario == 'float_visible':
                    self.assertEqual(result['source_range_preferred'], 120)


if __name__ == '__main__':
    unittest.main()
