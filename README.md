# vim-sgcomplete

File-backed, named autocomplete sources for Vim.

Register any number of plain-text files as independent completion sources
(names, companies, projects, ...), each bound to its own Insert-mode
invocation. Invoking a source pops up Vim's native completion menu with
only that source's candidates, filtered by the text immediately before the
cursor.

vim-sgcomplete never touches `'dictionary'`, `'thesaurus'`, `'iskeyword'`,
`'completefunc'`, `'omnifunc'`, `'spell'`, or any other built-in completion
setting, and never overwrites an existing mapping — all of Vim's own
completion behavior is left exactly as-is.

## Install

Any standard plugin manager works, e.g. with vim-plug:

```vim
Plug 'yourname/vim-sgcomplete'
```

## Quick start

```vim
let g:sgcomplete_sources = [
      \ {'name': 'names',     'file': '~/.vim/completions/names.txt',     'map': '<C-x><C-n>'},
      \ {'name': 'companies', 'file': '~/.vim/completions/companies.txt', 'map': '<C-x><C-c>'},
      \ ]
```

`~/.vim/completions/names.txt`:

```
John Smith
Jane Doe
```

In Insert mode: `Jo<C-x><C-n>` opens the popup with "John Smith"; selecting
it inserts the full value.

Full documentation: `:help sgcomplete` (see `doc/sgcomplete.txt`).

## Tests

```sh
test/run_tests.sh
```
