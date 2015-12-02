/// Small helper module to determine if the new std.concurrency interop features are present
module vibe.internal.newconcurrency;

enum bool newStdConcurrency = __VERSION__ >= 2067;
