#ifndef INSULATION_DEBUG_H
#define INSULATION_DEBUG_H

// Debug logging - disabled by default in release builds
#ifdef INSULATION_DEBUG_LOGS
    #define INSULATION_LOG(...) NSLog(__VA_ARGS__)
#else
    #define INSULATION_LOG(...) ((void)0)
#endif

#endif // INSULATION_DEBUG_H
