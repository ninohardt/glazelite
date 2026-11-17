#include "glazelite.h"

#include <glaze/json.hpp>
#include <glaze/core/istream_buffer.hpp>

#include <climits>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace {

using json = glz::generic_i64;
using array_t = json::array_t;
using object_t = json::object_t;

struct strict_opts : glz::opts {
  bool validate_trailing_whitespace = true;
};

inline bool is_json_space(char c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

inline bool is_r_int(int64_t v) { return v >= INT_MIN + 1LL && v <= INT_MAX; }

SEXP mkchar(std::string_view s) {
  if (s.size() > static_cast<size_t>(INT_MAX))
    throw std::runtime_error("JSON string is too long for R");
  // Rf_mkCharLenCE() would signal an R error for an embedded NUL.
  if (!s.empty() && std::memchr(s.data(), 0, s.size()) != nullptr)
    throw std::runtime_error("JSON strings containing \\u0000 cannot be represented in R");
  return Rf_mkCharLenCE(s.data(), static_cast<int>(s.size()), CE_UTF8);
}

// The scalar types seen in an array or data-frame column. Arrays whose
// non-null elements share one type become atomic vectors.
struct scalar_types {
  bool lgl = false, integer = false, real = false, str = false;

  // Returns false for arrays and objects, which are not scalars.
  bool add(const json& v) {
    if (v.get_if<std::nullptr_t>()) return true;
    if (v.get_if<bool>()) { lgl = true; return true; }
    if (auto p = v.get_if<int64_t>()) {
      if (is_r_int(*p)) integer = true; else real = true;
      return true;
    }
    if (v.get_if<double>()) { real = true; return true; }
    if (v.get_if<std::string>()) { str = true; return true; }
    return false;
  }

  bool any() const { return lgl || integer || real || str; }

  // The R vector type holding these values, or NILSXP when they are mixed.
  SEXPTYPE sexptype() const {
    const bool number = integer || real;
    if (lgl + number + str > 1) return NILSXP;
    if (lgl) return LGLSXP;
    if (str) return STRSXP;
    if (real) return REALSXP;
    if (integer) return INTSXP;
    return LGLSXP;  // only nulls: a logical NA column
  }
};

// An R vector under construction, pre-filled with NA.
struct column {
  SEXP x = R_NilValue;
  SEXPTYPE type = NILSXP;
  int* ints = nullptr;
  double* reals = nullptr;

  // The caller must protect x, directly or through its container.
  void attach(SEXP vec, R_xlen_t n) {
    x = vec;
    type = static_cast<SEXPTYPE>(TYPEOF(vec));
    switch (type) {
      case LGLSXP: ints = LOGICAL(x); for (R_xlen_t i = 0; i < n; ++i) ints[i] = NA_LOGICAL; break;
      case INTSXP: ints = INTEGER(x); for (R_xlen_t i = 0; i < n; ++i) ints[i] = NA_INTEGER; break;
      case REALSXP: reals = REAL(x); for (R_xlen_t i = 0; i < n; ++i) reals[i] = NA_REAL; break;
      default: for (R_xlen_t i = 0; i < n; ++i) SET_STRING_ELT(x, i, NA_STRING);
    }
  }

  // v is null or a scalar of the column's type.
  void set(R_xlen_t i, const json& v) {
    switch (type) {
      case LGLSXP:
        if (auto p = v.get_if<bool>()) ints[i] = *p ? 1 : 0;
        break;
      case INTSXP:
        if (auto p = v.get_if<int64_t>()) ints[i] = static_cast<int>(*p);
        break;
      case REALSXP:
        if (auto p = v.get_if<double>()) reals[i] = *p;
        else if (auto q = v.get_if<int64_t>()) reals[i] = static_cast<double>(*q);
        break;
      default:
        if (auto p = v.get_if<std::string>()) SET_STRING_ELT(x, i, mkchar(*p));
    }
  }
};

class converter {
 public:
  converter(bool simplify_vector, bool simplify_data_frame)
      : vector_(simplify_vector), frame_(simplify_vector && simplify_data_frame) {}

  SEXP value(const json& v, unsigned depth = 0) {
    if (depth > 1000) throw std::runtime_error("JSON nesting is too deep");
    if (v.get_if<std::nullptr_t>()) return R_NilValue;
    if (auto p = v.get_if<bool>()) return Rf_ScalarLogical(*p);
    if (auto p = v.get_if<int64_t>()) {
      if (is_r_int(*p)) return Rf_ScalarInteger(static_cast<int>(*p));
      return Rf_ScalarReal(static_cast<double>(*p));
    }
    if (auto p = v.get_if<double>()) return Rf_ScalarReal(*p);
    if (auto p = v.get_if<std::string>()) return Rf_ScalarString(mkchar(*p));
    if (auto p = v.get_if<array_t>()) return array(*p, depth);
    if (auto p = v.get_if<object_t>()) return object(*p, depth);
    throw std::runtime_error("unsupported Glaze JSON value");
  }

  SEXP array(const array_t& a, unsigned depth) {
    if (a.size() > static_cast<size_t>(R_XLEN_T_MAX))
      throw std::runtime_error("JSON array is too large for R");
    const R_xlen_t n = static_cast<R_xlen_t>(a.size());
    if (n > 0) {
      SEXP out = R_NilValue;
      if (a[0].get_if<object_t>()) {
        if (frame_) out = frame(a);
      } else if (vector_) {
        out = atomic(a);
      }
      if (out != R_NilValue) return out;
    }
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
    for (R_xlen_t i = 0; i < n; ++i) {
      SET_VECTOR_ELT(out, i, value(a[static_cast<size_t>(i)], depth + 1));
      tick();
    }
    UNPROTECT(1);
    return out;
  }

 private:
  bool vector_;
  bool frame_;
  size_t ticks_ = 0;

  void tick() {
    if ((++ticks_ & 65535) == 0) glazelite::check_interrupt();
  }

  SEXP object(const object_t& o, unsigned depth) {
    if (o.size() > static_cast<size_t>(R_XLEN_T_MAX))
      throw std::runtime_error("JSON object is too large for R");
    const R_xlen_t n = static_cast<R_xlen_t>(o.size());
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, n));
    R_xlen_t i = 0;
    for (const auto& [key, item] : o) {
      SET_STRING_ELT(names, i, mkchar(key));
      SET_VECTOR_ELT(out, i, value(item, depth + 1));
      ++i;
      tick();
    }
    Rf_setAttrib(out, R_NamesSymbol, names);
    UNPROTECT(2);
    return out;
  }

  // An array of scalars of one type becomes an atomic vector, with NA for
  // null. Returns R_NilValue when the array does not qualify.
  SEXP atomic(const array_t& a) {
    scalar_types types;
    for (const json& v : a) {
      if (!types.add(v)) return R_NilValue;
    }
    if (!types.any()) return R_NilValue;  // only nulls: keep a list of NULL
    const SEXPTYPE type = types.sexptype();
    if (type == NILSXP) return R_NilValue;
    const R_xlen_t n = static_cast<R_xlen_t>(a.size());
    SEXP out = PROTECT(Rf_allocVector(type, n));
    column col;
    col.attach(out, n);
    for (R_xlen_t i = 0; i < n; ++i) {
      col.set(i, a[static_cast<size_t>(i)]);
      tick();
    }
    UNPROTECT(1);
    return out;
  }

  // Finds or adds the column for a key. Records usually repeat the layout
  // of the first record, so the key's position is tried before the index.
  struct layout {
    std::vector<std::string_view> fields;
    std::unordered_map<std::string_view, size_t> index;

    static constexpr size_t npos = static_cast<size_t>(-1);

    size_t find(std::string_view key, size_t position) const {
      if (position < fields.size() && fields[position] == key) return position;
      auto it = index.find(key);
      return it == index.end() ? npos : it->second;
    }

    size_t add(std::string_view key) {
      fields.push_back(key);
      index.emplace(key, fields.size() - 1);
      return fields.size() - 1;
    }
  };

  // An array of objects whose fields are all scalars of one type per field
  // becomes a data frame. Returns R_NilValue when the array does not qualify.
  SEXP frame(const array_t& a) {
    if (a.size() > static_cast<size_t>(INT_MAX)) return R_NilValue;
    const R_xlen_t n = static_cast<R_xlen_t>(a.size());
    layout cols;
    std::vector<scalar_types> types;
    for (const json& record : a) {
      const object_t* o = record.get_if<object_t>();
      if (o == nullptr) return R_NilValue;
      size_t position = 0;
      for (const auto& [key, item] : *o) {
        size_t j = cols.find(key, position++);
        if (j == layout::npos) {
          j = cols.add(key);
          types.emplace_back();
        }
        if (!types[j].add(item)) return R_NilValue;
      }
      tick();
    }
    const size_t ncol = cols.fields.size();
    for (const scalar_types& t : types) {
      if (t.sexptype() == NILSXP) return R_NilValue;
    }

    SEXP out = PROTECT(Rf_allocVector(VECSXP, static_cast<R_xlen_t>(ncol)));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, static_cast<R_xlen_t>(ncol)));
    std::vector<column> columns(ncol);
    for (size_t j = 0; j < ncol; ++j) {
      SET_STRING_ELT(names, static_cast<R_xlen_t>(j), mkchar(cols.fields[j]));
      SEXP vec = Rf_allocVector(types[j].sexptype(), n);
      SET_VECTOR_ELT(out, static_cast<R_xlen_t>(j), vec);  // protects vec
      columns[j].attach(vec, n);
    }
    for (R_xlen_t i = 0; i < n; ++i) {
      const object_t& o = *a[static_cast<size_t>(i)].get_if<object_t>();
      size_t position = 0;
      for (const auto& [key, item] : o) {
        columns[cols.find(key, position++)].set(i, item);
      }
      tick();
    }
    Rf_setAttrib(out, R_NamesSymbol, names);
    SEXP row_names = PROTECT(Rf_allocVector(INTSXP, 2));
    INTEGER(row_names)[0] = NA_INTEGER;
    INTEGER(row_names)[1] = -static_cast<int>(n);
    Rf_setAttrib(out, R_RowNamesSymbol, row_names);
    SEXP cls = PROTECT(Rf_mkString("data.frame"));
    Rf_setAttrib(out, R_ClassSymbol, cls);
    UNPROTECT(4);
    return out;
  }
};

bool flag(SEXP x, const char* name) {
  if (TYPEOF(x) != LGLSXP || XLENGTH(x) != 1 || LOGICAL(x)[0] == NA_LOGICAL)
    throw std::runtime_error(std::string(name) + " must be TRUE or FALSE");
  return LOGICAL(x)[0] != 0;
}

// R strings are NUL-terminated, so Glaze's default null-terminated mode
// applies; it detects truncated documents. Content after the document is
// rejected as well.
bool parse(json& doc, const char* text) {
  std::string_view input(text);
  return !glz::read<strict_opts{}>(doc, input);
}

}  // namespace

extern "C" SEXP glazelite_from_json(SEXP txt, SEXP simplify_vector,
                                    SEXP simplify_data_frame) {
  return glazelite::guarded([&]() -> SEXP {
    if (TYPEOF(txt) != STRSXP || XLENGTH(txt) != 1 || STRING_ELT(txt, 0) == NA_STRING)
      throw std::runtime_error("txt must be one JSON string");
    converter convert(flag(simplify_vector, "simplifyVector"),
                      flag(simplify_data_frame, "simplifyDataFrame"));
    json doc;
    if (!parse(doc, Rf_translateCharUTF8(STRING_ELT(txt, 0))))
      throw std::runtime_error("invalid JSON input");
    return convert.value(doc);
  });
}

// Parses one JSON document per element of `lines` and converts them as if
// they were the elements of one JSON array. Blank lines are skipped. Returns
// NULL when there is no record.
extern "C" SEXP glazelite_from_ndjson(SEXP lines, SEXP simplify_vector,
                                      SEXP simplify_data_frame) {
  return glazelite::guarded([&]() -> SEXP {
    if (TYPEOF(lines) != STRSXP)
      throw std::runtime_error("lines must be a character vector");
    converter convert(flag(simplify_vector, "simplifyVector"),
                      flag(simplify_data_frame, "simplifyDataFrame"));
    const R_xlen_t n = XLENGTH(lines);
    array_t records;
    records.reserve(static_cast<size_t>(n));
    for (R_xlen_t i = 0; i < n; ++i) {
      SEXP line = STRING_ELT(lines, i);
      if (line == NA_STRING) continue;
      const char* text = Rf_translateCharUTF8(line);
      const char* p = text;
      while (is_json_space(*p)) ++p;
      if (*p == '\0') continue;
      json doc;
      if (!parse(doc, text))
        throw std::runtime_error("invalid JSON in record " +
                                 std::to_string(records.size() + 1));
      records.push_back(std::move(doc));
      if ((i & 65535) == 0) glazelite::check_interrupt();
    }
    if (records.empty()) return R_NilValue;
    return convert.array(records, 0);
  });
}

extern "C" SEXP glazelite_read_json(SEXP path, SEXP simplify_vector,
                                    SEXP simplify_data_frame) {
  return glazelite::guarded([&]() -> SEXP {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
      throw std::runtime_error("path must be one string");
    converter convert(flag(simplify_vector, "simplifyVector"),
                      flag(simplify_data_frame, "simplifyDataFrame"));
    const char* name = Rf_translateChar(STRING_ELT(path, 0));
    std::ifstream file(name, std::ios::binary);
    if (!file) throw std::runtime_error("cannot open JSON file");
    glz::basic_istream_buffer<std::ifstream, 1 << 20> buffer(file);
    json doc;
    if (auto ec = glz::read_json(doc, buffer); ec)
      throw std::runtime_error("invalid JSON file or token exceeds the input window");
    // The streaming reader stops after the first value. Require that only
    // whitespace follows it, as for JSON text.
    for (;;) {
      const char* rest = buffer.data();
      const size_t n = buffer.size();
      for (size_t i = 0; i < n; ++i) {
        if (!is_json_space(rest[i]))
          throw std::runtime_error("invalid JSON file: unexpected content after the document");
      }
      buffer.consume(n);
      if (!buffer.refill()) break;
    }
    // A file without any value leaves the document at its initial null.
    // Tell that apart from a literal null.
    if (doc.get_if<std::nullptr_t>()) {
      std::ifstream again(name, std::ios::binary);
      char c = 0;
      while (again.get(c) && is_json_space(c)) {}
      char tail[3] = {0, 0, 0};
      again.read(tail, 3);
      if (c != 'n' || again.gcount() != 3 || std::memcmp(tail, "ull", 3) != 0)
        throw std::runtime_error("invalid JSON file: no document found");
    }
    return convert.value(doc);
  });
}
