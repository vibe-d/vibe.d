module vibe.internal.interfaceproxy;

O asInterface(I, O)(O obj) if (is(I == interface) && is(O : I)) { return obj; }

/// Dummy declaration to enable forward compatibility with vibe-core 1.0.0
alias InterfaceProxy(I) = I;
