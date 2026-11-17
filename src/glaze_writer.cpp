#include "glazelite.h"
#include <R_ext/Arith.h>

#include <glaze/json.hpp>

#include <climits>
#include <cmath>
#include <cstring>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

class output {
 public:
  explicit output(const char* path = nullptr, bool append = false)
      : file_mode_(path != nullptr) {
    if (file_mode_) {
      file_.open(path, std::ios::binary |
          (append ? std::ios::app : std::ios::trunc));
      if (!file_) throw std::runtime_error("cannot open output file");
      buffer_.reserve(65536);
    }
  }

  void put(char c) { append(&c, 1); }

  void append(const char* s, size_t n) {
    if (!file_mode_) {
      if (n > static_cast<size_t>(INT_MAX) - buffer_.size())
        throw std::runtime_error("JSON exceeds R's string-size limit; use write_json()");
      buffer_.append(s, n);
      return;
    }
    if (n >= 65536) {
      flush();
      file_.write(s, static_cast<std::streamsize>(n));
      if (!file_) throw std::runtime_error("error writing JSON file");
    } else {
      if (buffer_.size() + n > 65536) flush();
      buffer_.append(s, n);
    }
  }

  void literal(std::string_view s) { append(s.data(), s.size()); }

  void flush() {
    if (file_mode_ && !buffer_.empty()) {
      file_.write(buffer_.data(), static_cast<std::streamsize>(buffer_.size()));
      if (!file_) throw std::runtime_error("error writing JSON file");
      buffer_.clear();
    }
  }

  void finish() {
    flush();
    if (file_mode_) {
      file_.flush();
      if (!file_) throw std::runtime_error("error finishing JSON file");
    }
  }

  const std::string& str() const { return buffer_; }

 private:
  bool file_mode_;
  std::ofstream file_;
  std::string buffer_;
};

class writer {
 public:
  writer(output& out, bool auto_unbox, const char* dataframe, const char* na,
         const char* factor, bool always_decimal, bool pretty = false)
      : out_(out), auto_unbox_(auto_unbox), dataframe_(dataframe),
        na_string_(std::strcmp(na, "string") == 0),
        factor_integer_(std::strcmp(factor, "integer") == 0),
        always_decimal_(always_decimal), pretty_(pretty) {}

  void value(SEXP x, unsigned depth = 0, bool force_array = false) {
    if (depth > 1000) throw std::runtime_error("JSON nesting is too deep");
    if (x == R_NilValue) { out_.literal("null"); return; }
    if (Rf_inherits(x, "data.frame")) { frame(x, depth); return; }
    SEXP dim = Rf_getAttrib(x, R_DimSymbol);
    if (dim != R_NilValue) {
      array(x, dim, depth); return;
    }
    if (TYPEOF(x) == VECSXP) {
      SEXP names = Rf_getAttrib(x, R_NamesSymbol);
      if (names != R_NilValue && XLENGTH(x) > 0) {
        object(x, names, depth);
      } else {
        out_.put('[');
        for (R_xlen_t i = 0, n = XLENGTH(x); i < n; ++i) {
          if (i) out_.put(',');
          newline(depth + 1);
          value(VECTOR_ELT(x, i), depth + 1);
          interrupt(i);
        }
        if (XLENGTH(x)) newline(depth);
        out_.put(']');
      }
      return;
    }
    if (!atomic(x)) throw std::runtime_error("unsupported R type");
    if (has_unsupported_class(x)) throw std::runtime_error("unsupported R class");
    R_xlen_t n = XLENGTH(x);
    if (n == 1 && auto_unbox_ && !force_array && !Rf_inherits(x, "AsIs")) {
      scalar(x, 0); return;
    }
    out_.put('[');
    for (R_xlen_t i = 0; i < n; ++i) {
      if (i) separator();
      scalar(x, i);
      interrupt(i);
    }
    out_.put(']');
  }

  void stream_batch(SEXP x) {
    if (Rf_inherits(x, "data.frame")) {
      const R_xlen_t n = frame_rows(x);
      for (R_xlen_t i = 0; i < n; ++i) {
        frame_row(x, i, 0);
        out_.put('\n');
        interrupt(i);
      }
      return;
    }
    if (TYPEOF(x) != VECSXP || Rf_getAttrib(x, R_NamesSymbol) != R_NilValue)
      throw std::runtime_error("stream batch must be a data frame or unnamed list of records");
    for (R_xlen_t i = 0, n = XLENGTH(x); i < n; ++i) {
      value(VECTOR_ELT(x, i));
      out_.put('\n');
      interrupt(i);
    }
  }

 private:
  output& out_;
  bool auto_unbox_;
  std::string dataframe_;
  bool na_string_;
  bool factor_integer_;
  bool always_decimal_;
  bool pretty_;
  std::string scratch_;
  R_xlen_t array_steps_ = 0;

  void separator() { out_.literal(pretty_ ? ", " : ","); }

  void newline(unsigned depth) {
    if (!pretty_) return;
    out_.put('\n');
    for (unsigned i = 0; i < depth; ++i) out_.literal("  ");
  }

  static bool atomic(SEXP x) {
    switch (TYPEOF(x)) {
      case LGLSXP: case INTSXP: case REALSXP: case STRSXP: return true;
      default: return false;
    }
  }

  static bool has_unsupported_class(SEXP x) {
    return Rf_getAttrib(x, R_ClassSymbol) != R_NilValue &&
           !Rf_inherits(x, "AsIs") && !Rf_inherits(x, "factor");
  }

  static bool is_matrix_column(SEXP column) {
    return TYPEOF(column) != VECSXP &&
           Rf_getAttrib(column, R_DimSymbol) != R_NilValue;
  }

  // The number of rows a data-frame column provides. Columns may be atomic
  // vectors, lists, matrices, or data frames.
  static R_xlen_t column_rows(SEXP column, unsigned depth) {
    if (Rf_inherits(column, "data.frame")) return frame_rows(column, depth + 1);
    SEXP dim = Rf_getAttrib(column, R_DimSymbol);
    if (dim != R_NilValue) {
      if (!atomic(column) || TYPEOF(dim) != INTSXP || XLENGTH(dim) != 2 ||
          INTEGER(dim)[0] < 0 || INTEGER(dim)[1] < 0 ||
          static_cast<R_xlen_t>(INTEGER(dim)[0]) * INTEGER(dim)[1] != XLENGTH(column))
        throw std::runtime_error(
            "data frame columns with dimensions must be atomic matrices");
      return INTEGER(dim)[0];
    }
    if (!atomic(column) && TYPEOF(column) != VECSXP)
      throw std::runtime_error("unsupported data frame column type");
    return XLENGTH(column);
  }

  // Also checks that all columns have the same number of rows, so that the
  // row writers never index past the end of a column.
  static R_xlen_t frame_rows(SEXP x, unsigned depth = 0) {
    if (depth > 1000) throw std::runtime_error("JSON nesting is too deep");
    if (XLENGTH(x)) {
      const R_xlen_t rows = column_rows(VECTOR_ELT(x, 0), depth);
      for (R_xlen_t col = 1, n = XLENGTH(x); col < n; ++col) {
        if (column_rows(VECTOR_ELT(x, col), depth) != rows)
          throw std::runtime_error("data frame columns differ in their number of rows");
      }
      SEXP names = Rf_getAttrib(x, R_NamesSymbol);
      if (TYPEOF(names) != STRSXP || XLENGTH(names) != XLENGTH(x))
        throw std::runtime_error("data frame columns must be named");
      return rows;
    }
    SEXP rn = Rf_getAttrib(x, R_RowNamesSymbol);
    if (TYPEOF(rn) == INTSXP && XLENGTH(rn) == 2 &&
        INTEGER(rn)[0] == NA_INTEGER) return -static_cast<R_xlen_t>(INTEGER(rn)[1]);
    return XLENGTH(rn);
  }

  static void interrupt(R_xlen_t i) {
    if ((i & 65535) == 0) glazelite::check_interrupt();
  }

  template <class T> void glaze(const T& v) {
    scratch_.clear();
    if (auto ec = glz::write_json(v, scratch_); ec)
      throw std::runtime_error("Glaze failed to encode a JSON value");
    out_.append(scratch_.data(), scratch_.size());
  }

  void number(double v) {
    scratch_.clear();
    if (auto ec = glz::write_json(v, scratch_); ec)
      throw std::runtime_error("Glaze failed to encode a JSON number");
    // Exponents already distinguish floating-point values from integers.
    if (always_decimal_ && scratch_.find_first_of(".eE") == std::string::npos)
      scratch_ += ".0";
    out_.append(scratch_.data(), scratch_.size());
  }

  void string(SEXP s) {
    if (s == NA_STRING) { missing("NA"); return; }
    const char* data = Rf_translateCharUTF8(s);
    const size_t n = std::strlen(data);
    if (n <= 4096) { glaze(std::string_view(data, n)); return; }
    // Glaze reserves up to twice the string length when writing one string.
    // Escape long strings in runs so file output stays bounded.
    out_.put('"');
    size_t start = 0;
    for (size_t i = 0; i < n; ++i) {
      const unsigned char c = static_cast<unsigned char>(data[i]);
      if (c >= 0x20 && c != '"' && c != '\\') continue;
      if (i > start) out_.append(data + start, i - start);
      switch (c) {
        case '"': out_.literal("\\\""); break;
        case '\\': out_.literal("\\\\"); break;
        case '\b': out_.literal("\\b"); break;
        case '\f': out_.literal("\\f"); break;
        case '\n': out_.literal("\\n"); break;
        case '\r': out_.literal("\\r"); break;
        case '\t': out_.literal("\\t"); break;
        default: {
          static constexpr char hex[] = "0123456789abcdef";
          const char esc[] = {'\\', 'u', '0', '0', hex[c >> 4], hex[c & 15]};
          out_.append(esc, 6);
        }
      }
      start = i + 1;
      if ((i & 1048575) == 0) glazelite::check_interrupt();
    }
    if (n > start) out_.append(data + start, n - start);
    out_.put('"');
  }

  void missing(const char* label) {
    if (na_string_) glaze(std::string_view(label));
    else out_.literal("null");
  }

  void scalar(SEXP x, R_xlen_t i) {
    if (Rf_inherits(x, "factor")) {
      int k = INTEGER_ELT(x, i);
      if (k == NA_INTEGER) { missing("NA"); return; }
      SEXP levels = Rf_getAttrib(x, R_LevelsSymbol);
      if (k < 1 || k > XLENGTH(levels)) throw std::runtime_error("invalid factor level");
      if (factor_integer_) glaze(k);
      else string(STRING_ELT(levels, k - 1));
      return;
    }
    if (has_unsupported_class(x)) throw std::runtime_error("unsupported R class");
    switch (TYPEOF(x)) {
      case STRSXP: string(STRING_ELT(x, i)); break;
      case LGLSXP: {
        int v = LOGICAL_ELT(x, i);
        if (v == NA_LOGICAL) missing("NA");
        else out_.literal(v ? "true" : "false");
        break;
      }
      case INTSXP: {
        int v = INTEGER_ELT(x, i);
        if (v == NA_INTEGER) missing("NA");
        else glaze(v);
        break;
      }
      case REALSXP: {
        double v = REAL_ELT(x, i);
        if (R_IsNA(v)) missing("NA");
        else if (R_IsNaN(v)) missing("NaN");
        else if (std::isinf(v)) missing(v < 0 ? "-Inf" : "Inf");
        else number(v);
        break;
      }
      default: throw std::runtime_error("unsupported atomic type");
    }
  }

  void object(SEXP x, SEXP names, unsigned depth) {
    out_.put('{');
    for (R_xlen_t i = 0, n = XLENGTH(x); i < n; ++i) {
      if (i) out_.put(',');
      newline(depth + 1);
      SEXP name = STRING_ELT(names, i);
      if (name == NA_STRING || !std::strlen(CHAR(name)))
        throw std::runtime_error("object names must be nonempty and non-missing");
      string(name);
      out_.literal(pretty_ ? ": " : ":");
      value(VECTOR_ELT(x, i), depth + 1);
      interrupt(i);
    }
    if (XLENGTH(x)) newline(depth);
    out_.put('}');
  }

  void frame_row(SEXP x, R_xlen_t row, unsigned depth) {
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
    const bool values = dataframe_ == "values";
    out_.put(values ? '[' : '{');
    bool first = true;
    for (R_xlen_t col = 0, n = XLENGTH(x); col < n; ++col) {
      SEXP column = VECTOR_ELT(x, col);
      const bool matrix = is_matrix_column(column);
      if (!values && !na_string_ && TYPEOF(column) != VECSXP && !matrix &&
          cell_missing(column, row)) continue;
      if (!first) {
        if (values) separator();
        else out_.put(',');
      }
      first = false;
      if (!values) {
        newline(depth + 1);
        string(STRING_ELT(names, col));
        out_.literal(pretty_ ? ": " : ":");
      }
      if (Rf_inherits(column, "data.frame")) {
        // A data-frame column contributes its own row as a nested record.
        frame_row(column, row, depth + 1);
      } else if (TYPEOF(column) == VECSXP) {
        value(VECTOR_ELT(column, row), depth + 1);
      } else if (matrix) {
        // A matrix column contributes its row as an array.
        const R_xlen_t nrow = INTEGER(Rf_getAttrib(column, R_DimSymbol))[0];
        const R_xlen_t ncol = INTEGER(Rf_getAttrib(column, R_DimSymbol))[1];
        out_.put('[');
        for (R_xlen_t j = 0; j < ncol; ++j) {
          if (j) separator();
          scalar(column, row + j * nrow);
        }
        out_.put(']');
      } else {
        scalar(column, row);
      }
    }
    if (!values && !first) newline(depth);
    out_.put(values ? ']' : '}');
  }

  static bool cell_missing(SEXP x, R_xlen_t i) {
    switch (TYPEOF(x)) {
      case LGLSXP: return LOGICAL_ELT(x, i) == NA_LOGICAL;
      case INTSXP: return INTEGER_ELT(x, i) == NA_INTEGER;
      case REALSXP: return !std::isfinite(REAL_ELT(x, i));
      case STRSXP: return STRING_ELT(x, i) == NA_STRING;
      default: return false;
    }
  }

  void frame(SEXP x, unsigned depth) {
    const R_xlen_t rows = frame_rows(x);
    const R_xlen_t cols = XLENGTH(x);
    if (dataframe_ == "columns") {
      SEXP names = Rf_getAttrib(x, R_NamesSymbol);
      out_.put('{');
      for (R_xlen_t c = 0; c < cols; ++c) {
        if (c) out_.put(',');
        newline(depth + 1);
        string(STRING_ELT(names, c));
        out_.literal(pretty_ ? ": " : ":");
        value(VECTOR_ELT(x, c), depth + 1, true);
      }
      if (cols) newline(depth);
      out_.put('}');
      return;
    }
    out_.put('[');
    for (R_xlen_t r = 0; r < rows; ++r) {
      if (r) out_.put(',');
      newline(depth + 1);
      frame_row(x, r, depth + 1);
      interrupt(r);
    }
    if (rows) newline(depth);
    out_.put(']');
  }

  void array(SEXP x, SEXP dim, unsigned depth) {
    if (!atomic(x) || has_unsupported_class(x))
      throw std::runtime_error("unsupported array type");
    if (TYPEOF(dim) != INTSXP || XLENGTH(dim) == 0)
      throw std::runtime_error("invalid array dimensions");
    const R_xlen_t ndim = XLENGTH(dim);
    if (ndim > 1000 || depth > 1000 - ndim)
      throw std::runtime_error("JSON nesting is too deep");
    std::vector<R_xlen_t> strides(static_cast<size_t>(ndim), 0);
    R_xlen_t size = 1;
    for (R_xlen_t axis = 0; axis < ndim; ++axis) {
      const int n = INTEGER(dim)[axis];
      if (n == NA_INTEGER || n < 0)
        throw std::runtime_error("invalid array dimensions");
      // An empty array never indexes data. Avoid overflow even when zero
      // dimensions accompany large, otherwise unrepresentable products.
      if (XLENGTH(x) == 0) continue;
      strides[axis] = size;
      if (n && size > R_XLEN_T_MAX / n)
        throw std::runtime_error("array dimensions are too large");
      size *= n;
    }
    if (XLENGTH(x) != 0 && size != XLENGTH(x))
      throw std::runtime_error("array dimensions do not match its length");
    array_level(x, dim, strides, 0, 0, depth);
  }

  void array_level(SEXP x, SEXP dim, const std::vector<R_xlen_t>& strides,
                   R_xlen_t axis, R_xlen_t offset, unsigned depth) {
    const R_xlen_t n = INTEGER(dim)[axis];
    const bool leaf = axis + 1 == XLENGTH(dim);
    out_.put('[');
    for (R_xlen_t i = 0; i < n; ++i) {
      if (i) {
        if (leaf) separator();
        else out_.put(',');
      }
      const R_xlen_t index = offset + i * strides[axis];
      if (leaf) scalar(x, index);
      else {
        newline(depth + 1);
        array_level(x, dim, strides, axis + 1, index, depth + 1);
      }
      interrupt(++array_steps_);
    }
    if (n && !leaf) newline(depth);
    out_.put(']');
  }
};

void check_options(SEXP path, SEXP unbox, SEXP df, SEXP na,
                   SEXP factor, SEXP decimal, SEXP pretty = R_NilValue) {
  if (path != R_NilValue && (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 ||
      STRING_ELT(path, 0) == NA_STRING))
    throw std::runtime_error("path must be one string");
  if (TYPEOF(unbox) != LGLSXP || XLENGTH(unbox) != 1 ||
      LOGICAL(unbox)[0] == NA_LOGICAL)
    throw std::runtime_error("auto_unbox must be TRUE or FALSE");
  if (TYPEOF(df) != STRSXP || XLENGTH(df) != 1 ||
      STRING_ELT(df, 0) == NA_STRING ||
      TYPEOF(na) != STRSXP || XLENGTH(na) != 1 ||
      STRING_ELT(na, 0) == NA_STRING ||
      TYPEOF(factor) != STRSXP || XLENGTH(factor) != 1 ||
      STRING_ELT(factor, 0) == NA_STRING)
    throw std::runtime_error("invalid JSON options");
  if (TYPEOF(decimal) != LGLSXP || XLENGTH(decimal) != 1 ||
      LOGICAL(decimal)[0] == NA_LOGICAL)
    throw std::runtime_error("always_decimal must be TRUE or FALSE");
  if (pretty != R_NilValue && (TYPEOF(pretty) != LGLSXP || XLENGTH(pretty) != 1 ||
      LOGICAL(pretty)[0] == NA_LOGICAL))
    throw std::runtime_error("pretty must be TRUE or FALSE");
}

}  // namespace

extern "C" SEXP glazelite_to_json(SEXP x, SEXP unbox, SEXP df, SEXP na,
                                  SEXP factor, SEXP decimal, SEXP pretty) {
  return glazelite::guarded([&]() -> SEXP {
    check_options(R_NilValue, unbox, df, na, factor, decimal, pretty);
    output out;
    writer w(out, LOGICAL(unbox)[0], CHAR(STRING_ELT(df, 0)),
             CHAR(STRING_ELT(na, 0)), CHAR(STRING_ELT(factor, 0)),
             LOGICAL(decimal)[0], LOGICAL(pretty)[0]);
    w.value(x);
    const auto& s = out.str();
    return Rf_ScalarString(Rf_mkCharLenCE(s.data(), static_cast<int>(s.size()), CE_UTF8));
  });
}

extern "C" SEXP glazelite_write_json(SEXP x, SEXP path, SEXP unbox,
                                      SEXP df, SEXP na, SEXP factor,
                                      SEXP decimal, SEXP pretty) {
  return glazelite::guarded([&]() -> SEXP {
    check_options(path, unbox, df, na, factor, decimal, pretty);
    output out(Rf_translateChar(STRING_ELT(path, 0)));
    writer w(out, LOGICAL(unbox)[0], CHAR(STRING_ELT(df, 0)),
             CHAR(STRING_ELT(na, 0)), CHAR(STRING_ELT(factor, 0)),
             LOGICAL(decimal)[0], LOGICAL(pretty)[0]);
    w.value(x);
    if (LOGICAL(pretty)[0]) out.put('\n');
    out.finish();
    return R_NilValue;
  });
}

extern "C" SEXP glazelite_stream_batch(SEXP x, SEXP path, SEXP unbox,
                                        SEXP na, SEXP append, SEXP factor,
                                        SEXP decimal) {
  SEXP df = PROTECT(Rf_mkString("rows"));
  SEXP result = glazelite::guarded([&]() -> SEXP {
    check_options(path, unbox, df, na, factor, decimal);
    if (TYPEOF(append) != LGLSXP || XLENGTH(append) != 1 ||
        LOGICAL(append)[0] == NA_LOGICAL)
      throw std::runtime_error("append must be TRUE or FALSE");
    output out(Rf_translateChar(STRING_ELT(path, 0)),
               LOGICAL(append)[0] == TRUE);
    writer w(out, LOGICAL(unbox)[0], "rows", CHAR(STRING_ELT(na, 0)),
             CHAR(STRING_ELT(factor, 0)), LOGICAL(decimal)[0]);
    w.stream_batch(x);
    out.finish();
    return R_NilValue;
  });
  UNPROTECT(1);
  return result;
}
