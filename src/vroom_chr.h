#include "altrep.h"
#include "vroom_vec.h"

#include <Rcpp.h>

Rcpp::CharacterVector read_chr(vroom_vec_info* info) {

  R_xlen_t n = info->idx->num_rows();

  Rcpp::CharacterVector out(n);

  auto i = 0;
  for (const auto& str : info->idx->get_column(info->column)) {
    auto val = info->locale->encoder_.makeSEXP(
        str.c_str(), str.c_str() + str.length(), false);

    // Look for NAs
    for (const auto& v : *info->na) {
      // We can just compare the addresses directly because they should now
      // both be in the global string cache.
      if (v == val) {
        val = NA_STRING;
        break;
      }
    }

    out[i++] = val;
  }

  return out;
}

#ifdef HAS_ALTREP

using namespace Rcpp;

struct vroom_string : vroom_vec {

public:
  static R_altrep_class_t class_t;

  // Make an altrep object of class `stdvec_double::class_t`
  static SEXP Make(vroom_vec_info* info) {

    SEXP out = PROTECT(R_MakeExternalPtr(info, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(out, vroom_vec::Finalize, FALSE);

    // make a new altrep object of class `vroom_string::class_t`
    SEXP res = R_new_altrep(class_t, out, R_NilValue);

    UNPROTECT(1);

    return res;
  }

  // ALTREP methods -------------------

  // What gets printed when .Internal(inspect()) is used
  static Rboolean Inspect(
      SEXP x,
      int pre,
      int deep,
      int pvec,
      void (*inspect_subtree)(SEXP, int, int, int)) {
    Rprintf(
        "vroom_string (len=%d, materialized=%s)\n",
        Length(x),
        R_altrep_data2(x) != R_NilValue ? "T" : "F");
    return TRUE;
  }

  // ALTSTRING methods -----------------

  static SEXP Val(SEXP vec, R_xlen_t i) {
    auto inf = Info(vec);

    auto str = Get(vec, i);

    auto val = inf.locale->encoder_.makeSEXP(
        str.c_str(), str.c_str() + str.length(), false);
    val = check_na(vec, val);

    return val;
  }

  static SEXP check_na(SEXP vec, SEXP val) {
    auto inf = Info(vec);

    // Look for NAs
    for (const auto& v : *Info(vec).na) {
      // We can just compare the addresses directly because they should now
      // both be in the global string cache.
      if (v == val) {
        val = NA_STRING;
        break;
      }
    }
    return val;
  }

  // the element at the index `i`
  //
  // this does not do bounds checking because that's expensive, so
  // the caller must take care of that
  static SEXP string_Elt(SEXP vec, R_xlen_t i) {
    SEXP data2 = R_altrep_data2(vec);
    if (data2 != R_NilValue) {
      return STRING_ELT(data2, i);
    }

    return Val(vec, i);
  }

  // --- Altvec
  static SEXP Materialize(SEXP vec) {
    SEXP data2 = R_altrep_data2(vec);
    if (data2 != R_NilValue) {
      return data2;
    }

    auto out = read_chr(&Info(vec));
    R_set_altrep_data2(vec, out);

    return out;
  }

  static void* Dataptr(SEXP vec, Rboolean writeable) {
    return STDVEC_DATAPTR(Materialize(vec));
  }

  // -------- initialize the altrep class with the methods above

  static void Init(DllInfo* dll) {
    class_t = R_make_altstring_class("vroom_string", "vroom", dll);

    // altrep
    R_set_altrep_Length_method(class_t, Length);
    R_set_altrep_Inspect_method(class_t, Inspect);

    // altvec
    R_set_altvec_Dataptr_method(class_t, Dataptr);
    R_set_altvec_Dataptr_or_null_method(class_t, Dataptr_or_null);

    // altstring
    R_set_altstring_Elt_method(class_t, string_Elt);
  }
};

R_altrep_class_t vroom_string::class_t;

// Called the package is loaded (needs Rcpp 0.12.18.3)
// [[Rcpp::init]]
void init_vroom_string(DllInfo* dll) { vroom_string::Init(dll); }

#else
void init_vroom_string(DllInfo* dll) {}
#endif
