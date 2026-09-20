%ctor {
    @autoreleasepool {
        __block NSUInteger probeAttempts = 0;
        __block void (^start)(void);
        start = ^{
            if (!PMDeviceSupports120Hz()) {
                // CADisplay may not expose modes during early image startup.
                // Retry briefly, but stop on confirmed 60Hz devices.
                if (probeAttempts++ >= 8) return;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    start();
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
        };
        start();
    }
}
