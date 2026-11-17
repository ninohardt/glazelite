#include "glazelite.h"
#include <R_ext/Arith.h>

#include <glaze/json.hpp>

#include <climits>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <limits>
#include <memory>
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

// Keeps R objects created while writing alive, and releases them when the
// scope ends, also when a C++ exception passes through.
class protect_guard {
 public:
  protect_guard() = default;
  protect_guard(const protect_guard&) = delete;
  protect_guard& operator=(const protect_guard&) = delete;
  ~protect_guard() { if (n_) UNPROTECT(n_); }
  SEXP add(SEXP x) { PROTECT(x); ++n_; return x; }

 private:
  int n_ = 0;
};

SEXP list_element(SEXP list, const char* name) {
  SEXP names = Rf_getAttrib(list, R_NamesSymbol);
  if (TYPEOF(list) == VECSXP && TYPEOF(names) == STRSXP) {
    for (R_xlen_t i = 0, n = XLENGTH(list); i < n; ++i) {
      if (std::strcmp(CHAR(STRING_ELT(names, i)), name) == 0) return VECTOR_ELT(list, i);
    }
  }
  throw std::runtime_error(std::string("missing JSON option: ") + name);
}

bool flag_option(SEXP list, const char* name) {
  SEXP x = list_element(list, name);
  if (TYPEOF(x) != LGLSXP || XLENGTH(x) != 1 || LOGICAL(x)[0] == NA_LOGICAL)
    throw std::runtime_error(std::string(name) + " must be TRUE or FALSE");
  return LOGICAL(x)[0] != 0;
}

int int_option(SEXP list, const char* name) {
  SEXP x = list_element(list, name);
  if (TYPEOF(x) != INTSXP || XLENGTH(x) != 1)
    throw std::runtime_error(std::string("invalid JSON option: ") + name);
  return INTEGER(x)[0];
}

std::string string_option(SEXP list, const char* name) {
  SEXP x = list_element(list, name);
  if (TYPEOF(x) != STRSXP || XLENGTH(x) != 1 || STRING_ELT(x, 0) == NA_STRING)
    throw std::runtime_error(std::string("invalid JSON option: ") + name);
  return CHAR(STRING_ELT(x, 0));
}

// The options of toJSON(), validated in R by .writer_options().
struct options {
  enum class layout { rows, columns, values };
  enum class posix { string, iso8601, epoch, mongo };

  layout dataframe = layout::rows;
  bool date_epoch = false;
  posix posixt = posix::string;
  bool factor_integer = false;
  bool null_as_list = true;
  bool na_string = false;
  bool auto_unbox = false;
  int digits = NA_INTEGER;     // NA: shortest text that round-trips
  bool digits_signif = false;
  int indent = -1;             // negative: compact output
  bool always_decimal = false;
  int rownames = NA_LOGICAL;   // NA: write character row names only
  SEXP time_format = R_NilValue;

  explicit options(SEXP x) {
    if (TYPEOF(x) != VECSXP) throw std::runtime_error("invalid JSON options");
    const std::string df = string_option(x, "dataframe");
    dataframe = df == "columns" ? layout::columns
              : df == "values" ? layout::values : layout::rows;
    date_epoch = string_option(x, "Date") == "epoch";
    const std::string px = string_option(x, "POSIXt");
    posixt = px == "ISO8601" ? posix::iso8601 : px == "epoch" ? posix::epoch
           : px == "mongo" ? posix::mongo : posix::string;
    factor_integer = string_option(x, "factor") == "integer";
    null_as_list = string_option(x, "null") == "list";
    na_string = string_option(x, "na") == "string";
    auto_unbox = flag_option(x, "auto_unbox");
    digits = int_option(x, "digits");
    digits_signif = flag_option(x, "digits_signif");
    indent = int_option(x, "indent");
    always_decimal = flag_option(x, "always_decimal");
    SEXP rn = list_element(x, "rownames");
    if (TYPEOF(rn) != LGLSXP || XLENGTH(rn) != 1)
      throw std::runtime_error("invalid JSON option: rownames");
    rownames = LOGICAL(rn)[0];
    time_format = list_element(x, "time_format");
    if (!Rf_isFunction(time_format))
      throw std::runtime_error("invalid JSON option: time_format");
  }
};

// How the elements of one atomic vector are written.
enum class kind { lgl, integer, real, str, factor, date, mongo };

struct vec {
  SEXP x = R_NilValue;       // the vector that is indexed, possibly converted
  kind k = kind::lgl;
  SEXP levels = R_NilValue;  // for factors
  bool unbox = false;        // marked with unbox()
  bool asis = false;         // wrapped in I()
};

struct frame_info;

struct column {
  SEXP x = R_NilValue;
  bool is_list = false;
  bool is_matrix = false;
  R_xlen_t nrow = 0, ncol = 0;           // of a matrix column
  vec v;                                 // atomic and matrix columns
  std::unique_ptr<frame_info> nested;    // data-frame columns
};

struct frame_info {
  SEXP names = R_NilValue;
  std::vector<column> cols;
  R_xlen_t rows = 0;
  SEXP row_names = R_NilValue;           // written as "_row" when not nil
};

// Days since 1970-01-01 to a proleptic Gregorian date.
void civil_from_days(int64_t z, int64_t& year, unsigned& month, unsigned& day) {
  z += 719468;
  const int64_t era = (z >= 0 ? z : z - 146096) / 146097;
  const unsigned doe = static_cast<unsigned>(z - era * 146097);
  const unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  const unsigned mp = (5 * doy + 2) / 153;
  day = doy - (153 * mp + 2) / 5 + 1;
  month = mp < 10 ? mp + 3 : mp - 9;
  year = static_cast<int64_t>(yoe) + era * 400 + (month <= 2 ? 1 : 0);
}

// Fixed notation with at most `digits` decimals and no trailing zeros, with
// the rounding jsonlite applies: half-way cases go to the even digit.
int format_fixed(double value, char* out, int digits) {
  static const double pow10[] = {1, 10, 100, 1000, 10000, 100000, 1000000,
                                 10000000, 100000000, 1000000000};
  const bool negative = value < 0;
  if (negative) value = -value;
  int whole = static_cast<int>(value);
  const double scaled = (value - whole) * pow10[digits];
  uint32_t frac = static_cast<uint32_t>(scaled);
  double diff = scaled - frac;
  if (diff > 0.5 || (diff == 0.5 && (frac & 1))) {
    ++frac;
    if (frac >= pow10[digits]) { frac = 0; ++whole; }  // 0.95 becomes 1
  }
  if (digits == 0) {
    diff = value - whole;
    if (diff > 0.5 || (diff == 0.5 && (whole & 1))) ++whole;
    frac = 0;
  }
  char* p = out;
  if (negative) *p++ = '-';
  p += std::snprintf(p, 16, "%d", whole);
  if (frac != 0) {
    char digits_text[16];
    int n = std::snprintf(digits_text, sizeof(digits_text), "%0*u", digits,
                          static_cast<unsigned>(frac));
    while (n > 0 && digits_text[n - 1] == '0') --n;
    *p++ = '.';
    std::memcpy(p, digits_text, static_cast<size_t>(n));
    p += n;
  }
  return static_cast<int>(p - out);
}

class writer {
 public:
  writer(output& out, const options& opt) : out_(out), opt_(opt) {}

  void value(SEXP x, unsigned depth = 0, bool force_array = false) {
    if (depth > 1000) throw std::runtime_error("JSON nesting is too deep");
    if (x == R_NilValue) {
      out_.literal(opt_.null_as_list ? "{}" : "null");
      return;
    }
    if (Rf_inherits(x, "data.frame")) {
      if (Rf_inherits(x, "scalar")) {
        // unbox() of a data frame with one row: the row itself.
        protect_guard guard;
        const frame_info f = prepare_frame(x, guard, depth);
        if (f.rows != 1) throw std::runtime_error("only data frames with one row can be unboxed");
        frame_row(f, 0, depth);
      } else {
        frame(x, depth);
      }
      return;
    }
    SEXP dim = Rf_getAttrib(x, R_DimSymbol);
    if (dim != R_NilValue) { array(x, dim, depth); return; }
    if (TYPEOF(x) == VECSXP && !Rf_inherits(x, "POSIXlt")) {
      SEXP names = Rf_getAttrib(x, R_NamesSymbol);
      if (names != R_NilValue) {
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
    protect_guard guard;
    const vec v = classify(x, guard);
    const R_xlen_t n = XLENGTH(v.x);
    if (n == 1 && !force_array && (v.unbox || (opt_.auto_unbox && !v.asis))) {
      scalar(v, 0);
      return;
    }
    vector(v, n);
  }

  // Writes records `from` (inclusive) to `to` (exclusive), one per line.
  void stream_batch(SEXP x, R_xlen_t from, R_xlen_t to) {
    if (Rf_inherits(x, "data.frame")) {
      protect_guard guard;
      const frame_info f = prepare_frame(x, guard, 0);
      if (to < 0 || to > f.rows) to = f.rows;
      for (R_xlen_t i = from < 0 ? 0 : from; i < to; ++i) {
        frame_row(f, i, 0);
        out_.put('\n');
        interrupt(i);
      }
      return;
    }
    if (TYPEOF(x) != VECSXP || Rf_getAttrib(x, R_NamesSymbol) != R_NilValue)
      throw std::runtime_error("stream batch must be a data frame or unnamed list of records");
    if (to < 0 || to > XLENGTH(x)) to = XLENGTH(x);
    for (R_xlen_t i = from < 0 ? 0 : from; i < to; ++i) {
      value(VECTOR_ELT(x, i));
      out_.put('\n');
      interrupt(i);
    }
  }

 private:
  output& out_;
  const options& opt_;
  std::string scratch_;
  R_xlen_t array_steps_ = 0;

  bool pretty() const { return opt_.indent >= 0; }

  void separator() { out_.literal(pretty() ? ", " : ","); }

  void colon() { out_.literal(pretty() ? ": " : ":"); }

  void newline(unsigned depth) {
    if (!pretty()) return;
    out_.put('\n');
    for (unsigned i = 0; i < depth; ++i) {
      for (int j = 0; j < opt_.indent; ++j) out_.put(' ');
    }
  }

  static void interrupt(R_xlen_t i) {
    if ((i & 65535) == 0) glazelite::check_interrupt();
  }

  // Determines how an atomic vector is written. Date-times are converted by
  // R's own formatting code; the result is protected by `guard`.
  vec classify(SEXP x, protect_guard& guard) const {
    vec v;
    v.x = x;
    bool factor = false, date = false, datetime = false;
    SEXP cls = Rf_getAttrib(x, R_ClassSymbol);
    if (TYPEOF(cls) == STRSXP) {
      for (R_xlen_t i = 0, n = XLENGTH(cls); i < n; ++i) {
        const char* name = CHAR(STRING_ELT(cls, i));
        if (!std::strcmp(name, "AsIs")) v.asis = true;
        else if (!std::strcmp(name, "scalar")) v.unbox = true;
        else if (!std::strcmp(name, "factor") || !std::strcmp(name, "ordered")) factor = true;
        else if (!std::strcmp(name, "Date")) date = true;
        else if (!std::strcmp(name, "POSIXct") || !std::strcmp(name, "POSIXlt") ||
                 !std::strcmp(name, "POSIXt")) datetime = true;
        else if (std::strcmp(name, "numeric") && std::strcmp(name, "integer") &&
                 std::strcmp(name, "character") && std::strcmp(name, "logical") &&
                 std::strcmp(name, "json") && std::strcmp(name, "glazelite_json") &&
                 std::strcmp(name, "noquote"))
          throw std::runtime_error(std::string("unsupported R class: ") + name);
      }
    }
    if (datetime) {
      SEXP call = guard.add(Rf_lang2(opt_.time_format, x));
      int failed = 0;
      SEXP res = R_tryEvalSilent(call, R_GlobalEnv, &failed);
      if (failed || res == nullptr)
        throw std::runtime_error("could not convert date-time values");
      v.x = guard.add(res);
      if (TYPEOF(v.x) == STRSXP) v.k = kind::str;
      else if (TYPEOF(v.x) == REALSXP)
        v.k = opt_.posixt == options::posix::mongo ? kind::mongo : kind::real;
      else throw std::runtime_error("could not convert date-time values");
      return v;
    }
    switch (TYPEOF(x)) {
      case LGLSXP: v.k = kind::lgl; break;
      case INTSXP: v.k = kind::integer; break;
      case REALSXP: v.k = kind::real; break;
      case STRSXP: v.k = kind::str; break;
      default: throw std::runtime_error("unsupported R type");
    }
    if (factor) {
      v.levels = Rf_getAttrib(x, R_LevelsSymbol);
      if (v.k != kind::integer || TYPEOF(v.levels) != STRSXP)
        throw std::runtime_error("invalid factor");
      v.k = kind::factor;
    } else if (date) {
      if (v.k != kind::integer && v.k != kind::real)
        throw std::runtime_error("invalid Date");
      if (!opt_.date_epoch) v.k = kind::date;
    }
    return v;
  }

  template <class T> void glaze(const T& value) {
    scratch_.clear();
    if (auto ec = glz::write_json(value, scratch_); ec)
      throw std::runtime_error("Glaze failed to encode a JSON value");
    out_.append(scratch_.data(), scratch_.size());
  }

  void number(double v) {
    if (opt_.digits == NA_INTEGER) {
      scratch_.clear();
      if (auto ec = glz::write_json(v, scratch_); ec)
        throw std::runtime_error("Glaze failed to encode a JSON number");
      // Exponents already distinguish floating-point values from integers.
      if (opt_.always_decimal && scratch_.find_first_of(".eE") == std::string::npos)
        scratch_ += ".0";
      out_.append(scratch_.data(), scratch_.size());
      return;
    }
    // Rounded output follows jsonlite: fixed notation for ordinary values,
    // and a number of significant digits for very large or small ones.
    char buf[64];
    int len;
    const double a = std::fabs(v);
    if (opt_.digits_signif) {
      len = std::snprintf(buf, sizeof(buf), "%.*g", opt_.digits > 15 ? 15 : opt_.digits, v);
    } else if (opt_.digits < 10 && a < 2147483647.0 && a > 1e-5) {
      len = format_fixed(v, buf, opt_.digits);
    } else {
      const double magnitude = a > 0 ? std::ceil(std::log10(a)) : 1.0;
      const double significant = std::fmin(17.0, std::fmax(1.0, magnitude) + opt_.digits);
      len = std::snprintf(buf, sizeof(buf), "%.*g", static_cast<int>(significant), v);
    }
    if (opt_.always_decimal && std::strspn(buf, "0123456789-") == static_cast<size_t>(len)) {
      buf[len++] = '.';
      buf[len++] = '0';
    }
    out_.append(buf, static_cast<size_t>(len));
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
    if (opt_.na_string) glaze(std::string_view(label));
    else out_.literal("null");
  }

  void date(double days) {
    if (!std::isfinite(days) || std::fabs(days) > 1e9) { missing("NA"); return; }
    int64_t year;
    unsigned month, day;
    civil_from_days(static_cast<int64_t>(std::floor(days)), year, month, day);
    char buf[40];
    const int len = std::snprintf(buf, sizeof(buf), "\"%04lld-%02u-%02u\"",
                                  static_cast<long long>(year), month, day);
    out_.append(buf, static_cast<size_t>(len));
  }

  static bool is_missing(const vec& v, R_xlen_t i) {
    switch (v.k) {
      case kind::lgl: return LOGICAL_ELT(v.x, i) == NA_LOGICAL;
      case kind::integer:
      case kind::factor: return INTEGER_ELT(v.x, i) == NA_INTEGER;
      case kind::str: return STRING_ELT(v.x, i) == NA_STRING;
      case kind::date:
        if (TYPEOF(v.x) == INTSXP) return INTEGER_ELT(v.x, i) == NA_INTEGER;
        return !std::isfinite(REAL_ELT(v.x, i));
      default: return !std::isfinite(REAL_ELT(v.x, i));
    }
  }

  void scalar(const vec& v, R_xlen_t i) {
    switch (v.k) {
      case kind::str: string(STRING_ELT(v.x, i)); break;
      case kind::lgl: {
        const int value = LOGICAL_ELT(v.x, i);
        if (value == NA_LOGICAL) missing("NA");
        else out_.literal(value ? "true" : "false");
        break;
      }
      case kind::integer: {
        const int value = INTEGER_ELT(v.x, i);
        if (value == NA_INTEGER) missing("NA");
        else glaze(value);
        break;
      }
      case kind::real: {
        const double value = REAL_ELT(v.x, i);
        if (R_IsNA(value)) missing("NA");
        else if (R_IsNaN(value)) missing("NaN");
        else if (std::isinf(value)) missing(value < 0 ? "-Inf" : "Inf");
        else number(value);
        break;
      }
      case kind::factor: {
        const int code = INTEGER_ELT(v.x, i);
        if (code == NA_INTEGER) { missing("NA"); break; }
        if (code < 1 || code > XLENGTH(v.levels)) throw std::runtime_error("invalid factor level");
        if (opt_.factor_integer) glaze(code);
        else string(STRING_ELT(v.levels, code - 1));
        break;
      }
      case kind::date: {
        if (TYPEOF(v.x) == INTSXP) {
          const int days = INTEGER_ELT(v.x, i);
          if (days == NA_INTEGER) missing("NA");
          else date(days);
        } else {
          date(REAL_ELT(v.x, i));
        }
        break;
      }
      case kind::mongo: {
        const double ms = REAL_ELT(v.x, i);
        if (!std::isfinite(ms)) { out_.literal("null"); break; }
        out_.literal("{\"$date\":");
        glaze(ms);
        out_.put('}');
        break;
      }
    }
  }

  void vector(const vec& v, R_xlen_t n) {
    out_.put('[');
    for (R_xlen_t i = 0; i < n; ++i) {
      if (i) separator();
      scalar(v, i);
      interrupt(i);
    }
    out_.put(']');
  }

  void object(SEXP x, SEXP names, unsigned depth) {
    if (TYPEOF(names) != STRSXP || XLENGTH(names) != XLENGTH(x))
      throw std::runtime_error("invalid names");
    out_.put('{');
    for (R_xlen_t i = 0, n = XLENGTH(x); i < n; ++i) {
      if (i) out_.put(',');
      newline(depth + 1);
      SEXP name = STRING_ELT(names, i);
      if (name == NA_STRING || !std::strlen(CHAR(name))) {
        // As in jsonlite, an element without a name is keyed by its position.
        glaze(std::to_string(i + 1));
      } else {
        string(name);
      }
      colon();
      value(VECTOR_ELT(x, i), depth + 1);
      interrupt(i);
    }
    if (XLENGTH(x)) newline(depth);
    out_.put('}');
  }

  // Checks a data frame and prepares its columns for row-wise writing. All
  // columns must provide the same number of rows, so that the row writers
  // never index past the end of a column.
  frame_info prepare_frame(SEXP x, protect_guard& guard, unsigned depth) const {
    if (depth > 1000) throw std::runtime_error("JSON nesting is too deep");
    if (TYPEOF(x) != VECSXP) throw std::runtime_error("invalid data frame");
    frame_info f;
    const R_xlen_t ncol = XLENGTH(x);
    f.names = Rf_getAttrib(x, R_NamesSymbol);
    if (ncol > 0 && (TYPEOF(f.names) != STRSXP || XLENGTH(f.names) != ncol))
      throw std::runtime_error("data frame columns must be named");
    // Automatic row names are expanded into a new vector, so protect them.
    SEXP row_names = guard.add(Rf_getAttrib(x, R_RowNamesSymbol));
    f.cols.resize(static_cast<size_t>(ncol));
    for (R_xlen_t j = 0; j < ncol; ++j) {
      column& col = f.cols[static_cast<size_t>(j)];
      col.x = VECTOR_ELT(x, j);
      R_xlen_t rows;
      SEXP dim = Rf_getAttrib(col.x, R_DimSymbol);
      if (Rf_inherits(col.x, "data.frame")) {
        col.nested = std::make_unique<frame_info>(prepare_frame(col.x, guard, depth + 1));
        rows = col.nested->rows;
      } else if (TYPEOF(col.x) == VECSXP && !Rf_inherits(col.x, "POSIXlt")) {
        if (dim != R_NilValue)
          throw std::runtime_error("data frame columns with dimensions must be atomic matrices");
        col.is_list = true;
        rows = XLENGTH(col.x);
      } else {
        col.v = classify(col.x, guard);
        if (dim != R_NilValue) {
          if (TYPEOF(dim) != INTSXP || XLENGTH(dim) != 2 ||
              INTEGER(dim)[0] < 0 || INTEGER(dim)[1] < 0 ||
              static_cast<R_xlen_t>(INTEGER(dim)[0]) * INTEGER(dim)[1] != XLENGTH(col.v.x))
            throw std::runtime_error("data frame columns with dimensions must be atomic matrices");
          col.is_matrix = true;
          col.nrow = INTEGER(dim)[0];
          col.ncol = INTEGER(dim)[1];
          rows = col.nrow;
        } else {
          rows = XLENGTH(col.v.x);
        }
      }
      if (j == 0) f.rows = rows;
      else if (rows != f.rows)
        throw std::runtime_error("data frame columns differ in their number of rows");
    }
    if (ncol == 0) f.rows = row_names == R_NilValue ? 0 : XLENGTH(row_names);
    // Character row names are data and are written as "_row", as in jsonlite.
    if (opt_.rownames != 0 && row_names != R_NilValue && XLENGTH(row_names) == f.rows &&
        (TYPEOF(row_names) == STRSXP || (opt_.rownames == 1 && TYPEOF(row_names) == INTSXP)))
      f.row_names = row_names;
    return f;
  }

  void row_name(const frame_info& f, R_xlen_t row) {
    if (TYPEOF(f.row_names) == STRSXP) string(STRING_ELT(f.row_names, row));
    else glaze(INTEGER_ELT(f.row_names, row));
  }

  void frame_row(const frame_info& f, R_xlen_t row, unsigned depth) {
    const bool values = opt_.dataframe == options::layout::values;
    out_.put(values ? '[' : '{');
    bool first = true;
    auto begin_field = [&](SEXP name) {
      if (!first) {
        if (values) separator();
        else out_.put(',');
      }
      first = false;
      if (!values) {
        newline(depth + 1);
        string(name);
        colon();
      }
    };
    for (size_t j = 0; j < f.cols.size(); ++j) {
      const column& col = f.cols[j];
      const bool plain = !col.nested && !col.is_list && !col.is_matrix;
      // Missing fields are omitted from records, as in jsonlite.
      if (plain && !values && !opt_.na_string && is_missing(col.v, row)) continue;
      begin_field(STRING_ELT(f.names, static_cast<R_xlen_t>(j)));
      if (col.nested) {
        // A data-frame column contributes its own row as a nested record.
        frame_row(*col.nested, row, depth + 1);
      } else if (col.is_list) {
        value(VECTOR_ELT(col.x, row), depth + 1);
      } else if (col.is_matrix) {
        // A matrix column contributes its row as an array.
        out_.put('[');
        for (R_xlen_t k = 0; k < col.ncol; ++k) {
          if (k) separator();
          scalar(col.v, row + k * col.nrow);
        }
        out_.put(']');
      } else {
        scalar(col.v, row);
      }
    }
    if (f.row_names != R_NilValue) {
      if (!first) {
        if (values) separator();
        else out_.put(',');
      }
      first = false;
      if (!values) {
        newline(depth + 1);
        out_.literal("\"_row\"");
        colon();
      }
      row_name(f, row);
    }
    if (!values && !first) newline(depth);
    out_.put(values ? ']' : '}');
  }

  void frame(SEXP x, unsigned depth) {
    protect_guard guard;
    const frame_info f = prepare_frame(x, guard, depth);
    if (opt_.dataframe == options::layout::columns) {
      out_.put('{');
      bool first = true;
      for (size_t j = 0; j < f.cols.size(); ++j) {
        const column& col = f.cols[j];
        if (!first) out_.put(',');
        first = false;
        newline(depth + 1);
        string(STRING_ELT(f.names, static_cast<R_xlen_t>(j)));
        colon();
        if (!col.nested && !col.is_list && !col.is_matrix) vector(col.v, f.rows);
        else value(col.x, depth + 1, true);
      }
      if (f.row_names != R_NilValue) {
        if (!first) out_.put(',');
        first = false;
        newline(depth + 1);
        out_.literal("\"_row\"");
        colon();
        out_.put('[');
        for (R_xlen_t i = 0; i < f.rows; ++i) {
          if (i) separator();
          row_name(f, i);
        }
        out_.put(']');
      }
      if (!first) newline(depth);
      out_.put('}');
      return;
    }
    out_.put('[');
    for (R_xlen_t r = 0; r < f.rows; ++r) {
      if (r) out_.put(',');
      newline(depth + 1);
      frame_row(f, r, depth + 1);
      interrupt(r);
    }
    if (f.rows) newline(depth);
    out_.put(']');
  }

  void array(SEXP x, SEXP dim, unsigned depth) {
    if (TYPEOF(x) == VECSXP) throw std::runtime_error("unsupported array type");
    protect_guard guard;
    const vec v = classify(x, guard);
    if (TYPEOF(dim) != INTSXP || XLENGTH(dim) == 0)
      throw std::runtime_error("invalid array dimensions");
    const R_xlen_t ndim = XLENGTH(dim);
    if (ndim > 1000 || depth > 1000 - ndim)
      throw std::runtime_error("JSON nesting is too deep");
    const R_xlen_t length = XLENGTH(v.x);
    std::vector<R_xlen_t> strides(static_cast<size_t>(ndim), 0);
    R_xlen_t size = 1;
    for (R_xlen_t axis = 0; axis < ndim; ++axis) {
      const int n = INTEGER(dim)[axis];
      if (n == NA_INTEGER || n < 0)
        throw std::runtime_error("invalid array dimensions");
      // An empty array never indexes data. Avoid overflow even when zero
      // dimensions accompany large, otherwise unrepresentable products.
      if (length == 0) continue;
      strides[static_cast<size_t>(axis)] = size;
      if (n && size > R_XLEN_T_MAX / n)
        throw std::runtime_error("array dimensions are too large");
      size *= n;
    }
    if (length != 0 && size != length)
      throw std::runtime_error("array dimensions do not match its length");
    array_level(v, dim, strides, 0, 0, depth);
  }

  void array_level(const vec& v, SEXP dim, const std::vector<R_xlen_t>& strides,
                   R_xlen_t axis, R_xlen_t offset, unsigned depth) {
    const R_xlen_t n = INTEGER(dim)[axis];
    const bool leaf = axis + 1 == XLENGTH(dim);
    out_.put('[');
    for (R_xlen_t i = 0; i < n; ++i) {
      if (i) {
        if (leaf) separator();
        else out_.put(',');
      }
      const R_xlen_t index = offset + i * strides[static_cast<size_t>(axis)];
      if (leaf) scalar(v, index);
      else {
        newline(depth + 1);
        array_level(v, dim, strides, axis + 1, index, depth + 1);
      }
      interrupt(++array_steps_);
    }
    if (n && !leaf) newline(depth);
    out_.put(']');
  }
};

const char* path_option(SEXP path) {
  if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
    throw std::runtime_error("path must be one string");
  return Rf_translateChar(STRING_ELT(path, 0));
}

SEXP as_r_string(const std::string& s) {
  return Rf_ScalarString(Rf_mkCharLenCE(s.data(), static_cast<int>(s.size()), CE_UTF8));
}

}  // namespace

extern "C" SEXP glazelite_to_json(SEXP x, SEXP opts) {
  return glazelite::guarded([&]() -> SEXP {
    const options opt(opts);
    output out;
    writer w(out, opt);
    w.value(x);
    return as_r_string(out.str());
  });
}

extern "C" SEXP glazelite_write_json(SEXP x, SEXP path, SEXP opts) {
  return glazelite::guarded([&]() -> SEXP {
    const options opt(opts);
    output out(path_option(path));
    writer w(out, opt);
    w.value(x);
    if (opt.indent >= 0) out.put('\n');
    out.finish();
    return R_NilValue;
  });
}

// Writes the records of one batch as newline-delimited JSON. With a path
// they are appended to that file; without one they are returned as a string.
// `range` holds the first and the last record to write (one-based), or is
// NULL for the whole batch.
extern "C" SEXP glazelite_stream_batch(SEXP x, SEXP path, SEXP opts, SEXP range) {
  return glazelite::guarded([&]() -> SEXP {
    const options opt(opts);
    R_xlen_t from = 0, to = -1;
    if (range != R_NilValue) {
      if (TYPEOF(range) != REALSXP || XLENGTH(range) != 2 ||
          !(REAL(range)[0] >= 1) || !(REAL(range)[1] >= 0))
        throw std::runtime_error("invalid record range");
      from = static_cast<R_xlen_t>(REAL(range)[0]) - 1;
      to = static_cast<R_xlen_t>(REAL(range)[1]);
    }
    if (path == R_NilValue) {
      output out;
      writer w(out, opt);
      w.stream_batch(x, from, to);
      return as_r_string(out.str());
    }
    output out(path_option(path), true);
    writer w(out, opt);
    w.stream_batch(x, from, to);
    out.finish();
    return R_NilValue;
  });
}
