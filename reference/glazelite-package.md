# glazelite: Fast JSON Reading and Writing with the Glaze C++ Library

glazelite reads and writes JSON using the header-only C++ library
[Glaze](https://github.com/stephenberry/glaze) by Stephen Berry. It
offers a subset of the 'jsonlite' interface:

## Details

- [`jsonlite::toJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html)
  and
  [`jsonlite::fromJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html)
  convert between R objects and JSON text.

- [`jsonlite::write_json()`](https://rdrr.io/pkg/jsonlite/man/read_json.html)
  and
  [`jsonlite::read_json()`](https://rdrr.io/pkg/jsonlite/man/read_json.html)
  work directly on files. Writing is incremental, so a document may be
  larger than a single R string.

- [`jsonlite::stream_out()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html)
  and
  [`jsonlite::stream_in()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html)
  write and read newline-delimited JSON (NDJSON) in batches.

## Credits

All JSON encoding and parsing is done by Glaze, which is bundled with
the package under the MIT license. Glaze in turn includes code from the
'fast_float', 'zmij' and 'xxh64' projects. See the file `COPYRIGHTS` in
the installed package for details.

## See also

Useful links:

- <https://github.com/ninohardt/glazelite>

- Report bugs at <https://github.com/ninohardt/glazelite/issues>

## Author

**Maintainer**: Nino Hardt <me@ninohardt.com>
([ORCID](https://orcid.org/0000-0001-5215-6216)) \[copyright holder\]

Other contributors:

- Stephen Berry (Author of the bundled 'Glaze' library) \[contributor,
  copyright holder\]

- Daniel Lemire (Author of 'fast_float', bundled with 'Glaze')
  \[contributor, copyright holder\]

- João Paulo Magalhaes (Author of 'fast_float', bundled with 'Glaze')
  \[contributor, copyright holder\]

- The fast_float authors ('fast_float', bundled with 'Glaze')
  \[copyright holder\]

- Victor Zverovich (Author of 'zmij', ported in the bundled 'Glaze'
  headers) \[contributor, copyright holder\]

- Daniel Kirchner (Author of the 'xxh64' implementation bundled with
  'Glaze') \[contributor, copyright holder\]
