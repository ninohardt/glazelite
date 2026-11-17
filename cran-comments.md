## Submission

This is a new submission.

## Test environments

* Windows 10 x64, R 4.5.2, Rtools45 (GCC 14.2.0)
* Windows 10 x64, R 4.6.2, Rtools45 (GCC 14.2.0)

<!-- Before submitting, add the results of the other platforms here:
     win-builder (R-devel, R-release), macOS builder
     (https://mac.r-project.org/macbuilder/submit.html) and a Linux check
     (R-hub or a local `R CMD check --as-cran`). -->

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  New submission

## C++23

The package requires C++23 (`SystemRequirements: C++23`, `CXX_STD = CXX23`),
because the bundled 'Glaze' library is written in C++23. It therefore needs a
recent compiler (GCC >= 13, Clang >= 19 are what upstream tests with) and will
not build on platforms whose compiler lacks C++23 support.

## Bundled code

The package bundles a subset of the header-only C++ library 'Glaze'
(<https://github.com/stephenberry/glaze>, MIT license) under
`inst/include/glaze`. 'Glaze' contains code from 'fast_float', 'zmij' and an
'xxh64' implementation. All copyright holders are listed in `Authors@R` and,
with their licenses, in `inst/COPYRIGHTS`.

The only changes to the upstream headers remove the suppression of compiler
diagnostics, to comply with the CRAN policy: `#pragma GCC/clang diagnostic
ignored` lines were replaced by comments, and two `unsigned __int128` type
aliases were marked with `__extension__`. The changes are documented in
`inst/COPYRIGHTS`.
