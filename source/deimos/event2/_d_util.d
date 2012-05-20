module deimos.event2._d_util;

public import core.stdc.config;

package:

// Very boiled down version because we cannot use std.traits without causing
// DMD to create a ModuleInfo reference for _d_util, which would require users
// to include the Deimos files in the build.
template ExternC(T) if (is(typeof(*(T.init)) P == function)) {
	static if (is(typeof(*(T.init)) R == return)) {
		static if (is(typeof(*(T.init)) P == function)) {
			alias extern(C) R function(P) ExternC;
		}
	}
}
