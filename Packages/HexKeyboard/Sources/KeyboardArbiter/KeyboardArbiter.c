#include "KeyboardArbiter.h"
#include <mach-o/dyld.h>
#include <objc/runtime.h>
#include <string.h>

static BOOL enabled(id self, SEL _cmd) { return YES; }

bool HexEnableKeyboardArbiter(void) {
    Class arbiter = objc_getClass("_UIKeyboardArbiterClient");
    Method method = arbiter ? class_getClassMethod(arbiter, sel_registerName("enabled")) : NULL;
    if (!method) return false;
    method_setImplementation(method, (IMP)enabled);
    return true;
}

__attribute__((constructor)) static void enableInKeyboards(void) {
    char path[1024];
    uint32_t size = sizeof path;
    if (_NSGetExecutablePath(path, &size) == 0 && strstr(path, ".appex/")) HexEnableKeyboardArbiter();
}
