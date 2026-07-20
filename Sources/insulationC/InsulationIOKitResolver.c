#include <dlfcn.h>
#include <IOKit/IOKitLib.h>
#include <stdbool.h>

/* Resolve IORegistryEntrySetCFProperty/CFProperties via dlsym.
   Called from InsulationIOKitProbe.m to avoid dlsym in ObjC sources. */

bool InsulationIOKitResolveSetCFProperty(void **out_setCFProperty, void **out_setCFProperties) {
    if (!out_setCFProperty || !out_setCFProperties) return false;
    *out_setCFProperty = dlsym(RTLD_DEFAULT, "IORegistryEntrySetCFProperty");
    *out_setCFProperties = dlsym(RTLD_DEFAULT, "IORegistryEntrySetCFProperties");
    return (*out_setCFProperty != NULL && *out_setCFProperties != NULL);
}