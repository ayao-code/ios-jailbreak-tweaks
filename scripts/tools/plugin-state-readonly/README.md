# Narrow external plugin state reader

Reads exactly five bytes from an explicitly supplied, independently verified
SpringBoard data address. Verify device, PID/start time, mapped binary UUID,
image base and static data offset before use. No process enumeration, heap
scan, injection, debugger attach, thread suspend/resume, task write, debug-flag
change, or remote method invocation. It exits if task access is denied; do not
weaken target protections to retry. Privileged task access still carries risk.
The five values alone are not proof of the complete rendering cause.

Build as standalone arm64 C using the local iPhoneOS SDK; sign with included
entitlements. Deployment only in an authorized temporary diagnostics directory.

The `metadata` mode accepts bounded address/size requests on stdin, returning
hex bytes. It is for following verified Mach-O/Objective-C/view metadata links,
not heap scanning or private app content. Per read 64 KiB, total 16 MiB and
4000 requests maximum. No writes or method calls, no thread suspension.
The caller must avoid message/account objects and stop on invalid structure.
