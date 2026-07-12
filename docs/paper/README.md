# FatigueMeter — journal-style paper (LaTeX)

`fatiguemeter.tex` is a **standalone**, journal-formatted version of the FatigueMeter white paper: Vancouver (numbered) citations, `hyperref` cross-linking between sections/equations/tables/references, and hyperlinked DOIs/URLs in the reference list. It contains no references to reviewers, revisions, or the other repository documents.

## Build

Requires a LaTeX distribution (TeX Live or MiKTeX). Run twice so cross-references and citations resolve (the bibliography is an inline `thebibliography`, so **no** `bibtex`/`biber` step is needed):

```sh
pdflatex fatiguemeter.tex
pdflatex fatiguemeter.tex
```

or, more simply:

```sh
latexmk -pdf fatiguemeter.tex
```

## Notes

- **Authors/affiliation** are placeholders in the `\author{}` block — edit them before distributing.
- Packages used are standard and ship with full TeX distributions: `amsmath`, `booktabs`, `tabularx`, `titlesec`, `hyperref`, `xcolor`, `microtype`, `enumitem`, `caption`, `abstract`.
- Citation style is numeric Vancouver via `thebibliography`; references are ordered by first appearance in the text.
