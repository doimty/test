#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#define jbroot(path) (path)
#endif
#import <spawn.h>
#import <Foundation/Foundation.h>
#import "./PSSpecifier/PSSpecifier.h"

int insulationPrefsPostRuntimeState(int thermalMode, int cpuMode);

static NSString *_Nonnull rootlessPath(NSString* _Nonnull path) {
  return jbroot(path);
}
