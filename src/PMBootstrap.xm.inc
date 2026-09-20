static NSUInteger PMBootstrapProbeAttempts = 0;
static void (^PMBootstrapStart)(void) = nil;

%ctor {
    @autoreleasepool {
        PMBootstrapStart = ^{
            if (!PMDeviceSupports120Hz()) {
                // CADisplay may not expose modes during early image startup.
                // Retry briefly, but stop after a bounded number of attempts.
                if (PMBootstrapProbeAttempts++ >= 8) {
                    PMBootstrapStart = nil;
                    return;
                }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (PMBootstrapStart) PMBootstrapStart();
                });
                return;
            }

            %init;
            // Dynamic source protection for ALL processes
            PMInstallDynamicSourceHooks();
            if (PMIsTargetProcess()) {
                PMInstallHooks();
                PMHookContextMenuInteractionIfAvailable();
                PMHookEditMenuInteractionIfAvailable();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    PMInstallDynamicSourceHooks();
                    PMGlobalSBSetup();
                });
            } else {
                // Initialize persistent 120Hz source after main display is ready
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    PMInstallDynamicSourceHooks();
                    PMAppEnsurePersistentSource();
                });
                // Re-apply when app returns from background
                [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
                    PMAppRefreshPersistentSource();
                }];
            }
            PMBootstrapStart = nil;
        };
        PMBootstrapStart();
    }
}
