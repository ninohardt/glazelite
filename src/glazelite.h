#ifndef GLAZELITE_H
#define GLAZELITE_H

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Utils.h>

#include <cstdio>
#include <exception>
#include <stdexcept>

namespace glazelite {

// R signals errors and interrupts with longjmp, which skips C++ destructors
// (open files, buffers). These helpers keep R's non-local exits outside the
// scopes that own C++ resources.

struct interrupted : std::runtime_error {
  interrupted() : std::runtime_error("JSON operation interrupted") {}
};

inline void check_interrupt_fn(void*) { R_CheckUserInterrupt(); }

// Throws a C++ exception instead of jumping when the user interrupts.
inline void check_interrupt() {
  if (R_ToplevelExec(check_interrupt_fn, nullptr) == FALSE) throw interrupted();
}

// Runs f(), converting C++ exceptions to R errors only after every C++
// object created by f() has been destroyed.
template <class F> SEXP guarded(F&& f) {
  static char message[1024];
  try {
    return f();
  } catch (const std::exception& e) {
    std::snprintf(message, sizeof(message), "%s", e.what());
  } catch (...) {
    std::snprintf(message, sizeof(message), "unknown C++ error");
  }
  Rf_error("%s", message);
  return R_NilValue;  // not reached
}

}  // namespace glazelite

#endif
