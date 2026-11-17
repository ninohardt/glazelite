#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

extern SEXP glazelite_to_json(SEXP, SEXP);
extern SEXP glazelite_write_json(SEXP, SEXP, SEXP);
extern SEXP glazelite_stream_batch(SEXP, SEXP, SEXP, SEXP);
extern SEXP glazelite_from_json(SEXP, SEXP, SEXP, SEXP);
extern SEXP glazelite_from_ndjson(SEXP, SEXP, SEXP, SEXP);
extern SEXP glazelite_read_json(SEXP, SEXP, SEXP, SEXP);
extern SEXP glazelite_validate(SEXP);
extern SEXP glazelite_minify(SEXP);
extern SEXP glazelite_prettify(SEXP, SEXP);

static const R_CallMethodDef call_methods[] = {
  {"glazelite_to_json", (DL_FUNC) &glazelite_to_json, 2},
  {"glazelite_write_json", (DL_FUNC) &glazelite_write_json, 3},
  {"glazelite_stream_batch", (DL_FUNC) &glazelite_stream_batch, 4},
  {"glazelite_from_json", (DL_FUNC) &glazelite_from_json, 4},
  {"glazelite_from_ndjson", (DL_FUNC) &glazelite_from_ndjson, 4},
  {"glazelite_read_json", (DL_FUNC) &glazelite_read_json, 4},
  {"glazelite_validate", (DL_FUNC) &glazelite_validate, 1},
  {"glazelite_minify", (DL_FUNC) &glazelite_minify, 1},
  {"glazelite_prettify", (DL_FUNC) &glazelite_prettify, 2},
  {NULL, NULL, 0}
};

void R_init_glazelite(DllInfo* dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
