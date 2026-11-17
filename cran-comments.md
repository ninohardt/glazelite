## Submission

This is a new submission.

## Test environments

* Windows 10 x64, R 4.5.2 and R 4.6.2, Rtools45 (GCC 14.2.0), local
* win-builder, Windows Server 2022 x64, R-devel (2026-11-16 r90914),
  GCC 14.3.0 (an earlier build of this version)
* GitHub Actions, Ubuntu 26.04, GCC 15.2.0: R-devel (2026-11-16 r90914),
  R 4.6.2 and R 4.5.3
* GitHub Actions, macOS 26 (arm64), Apple clang 21.0.0, R 4.6.2
* GitHub Actions, Windows Server 2022 x64, GCC 14.3.0, R 4.6.2

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  New submission

## C++23

The package requires C++23 (`SystemRequirements: C++23`, `CXX_STD = CXX23`),
because the bundled 'Glaze' library is written in C++23. It therefore needs a
recent compiler (GCC >= 13, Clang >= 19 are what upstream tests with) and will
not build on platforms whose compiler lacks C++23 support. I could not test
Apple clang 14, which some of the CRAN macOS check machines use.

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
