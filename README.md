## Information

This is an unofficial standalone version of the [System Informer](https://github.com/winsiderss/systeminformer) (formerly Process Hacker) Native API headers (phnt). The headers are directly pulled from the System Informer master branch every night and may contain untested code.
If you are looking for a stable release check out the [official phnt repository](https://github.com/winsiderss/phnt)

***

This collection of Native API header files has been maintained since 2009 for the Process Hacker project, and is the most up-to-date set of Native API definitions that we know of. We have gathered these definitions from official Microsoft header files and symbol files, as well as a lot of reverse engineering and guessing. See `phnt.h` for more information.

## Usage

First make sure that your program is using the latest Windows SDK.

These header files are designed to be used by user-mode programs. Instead of `#include <windows.h>`, place

```
#include <phnt_windows.h>
#include <phnt.h>
```

at the top of your program. The first line provides access to the Win32 API as well as the `NTSTATUS` values. The second line provides access to the entire Native API.

By default every definition is included, equivalent to:

```c
#define PHNT_VERSION PHNT_WINDOWS_NEW
```

To restrict the definitions to those present in a particular Windows release, define `PHNT_VERSION` before including `phnt.h`:

```c
#define PHNT_VERSION PHNT_WINDOWS_VISTA   // Windows Vista
#define PHNT_VERSION PHNT_WINDOWS_7       // Windows 7
#define PHNT_VERSION PHNT_WINDOWS_10      // Windows 10, version 1507
#define PHNT_VERSION PHNT_WINDOWS_11_24H2 // Windows 11, version 24H2
```

See the `PHNT_WINDOWS_*` list at the top of [`phnt.h`](phnt.h) for the full set.

