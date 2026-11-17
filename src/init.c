#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

extern SEXP glazelite_to_json(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP glazelite_write_json(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP glazelite_stream_batch(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP glazelite_from_json(SEXP, SEXP, SEXP);
extern SEXP glazelite_from_ndjson(SEXP, SEXP, SEXP);
extern SEXP glazelite_read_json(SEXP, SEXP, SEXP);

static const R_CallMethodDef call_methods[] = {
  {"glazelite_to_json", (DL_FUNC) &glazelite_to_json, 7},
  {"glazelite_write_json", (DL_FUNC) &glazelite_write_json, 8},
  {"glazelite_stream_batch", (DL_FUNC) &glazelite_stream_batch, 7},
  {"glazelite_from_json", (DL_FUNC) &glazelite_from_json, 3},
  {"glazelite_from_ndjson", (DL_FUNC) &glazelite_from_ndjson, 3},
  {"glazelite_read_json", (DL_FUNC) &glazelite_read_json, 3},
  {NULL, NULL, 0}
};

void R_init_glazelite(DllInfo* dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
