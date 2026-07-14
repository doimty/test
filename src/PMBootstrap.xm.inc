%ctor {
    @autoreleasepool {
        if (PMDeviceSupports120Hz()) {
            %init;
            // Dynamic source protection for ALL processes
            PMInstallDynamicSourceHooks();
            if (PMIsTargetProcess()) {
#if PM_ENABLE_FLOAT_ZOOM_PROBE
                PMFloatProbeInjectedCount += 1;
                PMFloatWriteState(@"ctor.injected.sb", @"com.apple.springboard", YES);
#endif
                PMInstallHooks();
                PMHookContextMenuInteractionIfAvailable();
                PMHookEditMenuInteractionIfAvailable();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    PMGlobalSBSetup();
                });
            }
            if (!PMIsTargetProcess()) {
                // Register Darwin notification state so SpringBoard knows
                // this app has our hooks injected (skip keepalive)
                @try {
                    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
                    if (bundleID) {
                        char name[256];
                        snprintf(name, sizeof(name), "com.doimty.pm120.hooked.%s", [bundleID UTF8String]);
                        int regToken;
                        notify_register_check(name, &regToken);
                        notify_set_state(regToken, 1);
                        // Do NOT cancel — token must stay alive for state to persist
                    }
                } @catch (__unused NSException *e) {}
                PMFloatProbeInjectedCount += 1;
#if PM_ENABLE_FLOAT_ZOOM_PROBE
                PMFloatWriteState(@"ctor.injected", PMBundleID() ?: @"", YES);
#endif
                // Initialize persistent 120Hz source after main display is ready
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    PMAppEnsurePersistentSource();
                });
                // Re-apply when app returns from background
                [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
                    PMAppRefreshPersistentSource();
                }];
            }
        }
    }
}
