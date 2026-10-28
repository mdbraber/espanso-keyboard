#include <stdbool.h>

/// Switches on UIKit's keyboard arbiter client, which knows the app a keyboard is serving but stays off in a keyboard
/// unless `+[_UIKeyboardArbiterClient enabled]` says otherwise. It runs as the keyboard loads, because UIKit decides
/// once, early, whether the client exists; calling it again is harmless. False when UIKit has no such class.
bool HexEnableKeyboardArbiter(void);
