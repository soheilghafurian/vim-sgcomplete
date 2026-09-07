" autoload/sgcomplete.vim
" Core logic for vim-sgcomplete: file-backed, named completion sources.
"
" Design note: completion is triggered by calling complete() directly from
" an insert-mode mapping. We deliberately never touch 'completefunc',
" 'omnifunc', 'dictionary', 'thesaurus', 'iskeyword', 'spell', or any other
" built-in completion option, so all of Vim's native completion mechanisms
" (i_CTRL-X_CTRL-K, i_CTRL-X_CTRL-T, i_CTRL-X_CTRL-N/P, i_CTRL-X_CTRL-F,
" i_CTRL-X_CTRL-O, i_CTRL-X_CTRL-U/S, ...) keep working exactly as before.

if exists('g:autoloaded_sgcomplete')
  finish
endif
let g:autoloaded_sgcomplete = 1

" name -> {'file': path, 'map': mapping, 'ftime': cached mtime, 'candidates': [...]}
let s:sources = {}

function! s:Warn(msg) abort
  echohl WarningMsg
  echom '[sgcomplete] ' . a:msg
  echohl None
endfunction

" Read a completion file into a list of non-blank lines.
" Missing/unreadable/empty files degrade to an empty candidate list instead
" of raising an error, per spec.
function! s:ReadCandidates(file) abort
  let path = expand(a:file)
  if empty(path) || !filereadable(path)
    return []
  endif
  try
    let lines = readfile(path)
  catch
    call s:Warn('could not read completion file: ' . path)
    return []
  endtry
  return filter(lines, {_, v -> v !~# '^\s*$'})
endfunction

" Return cached candidates for a:name, re-reading the backing file only
" when it has changed on disk (or hasn't been read yet).
"
" src.file may be a relative path, which resolves against Vim's current
" working directory -- this is what lets a single source registration
" transparently serve different content in different projects (see
" doc/sgcomplete.txt, "per-project sources"). Because of that, the cache
" must key on the *resolved path* as well as its mtime: keying on mtime
" alone would wrongly serve project A's cached candidates to project B
" after a `:cd`, whenever the two backing files happen to share an mtime.
function! s:GetCandidates(name) abort
  let src = s:sources[a:name]
  let path = expand(src.file)
  " A plain relative path (no '~', '$VAR', wildcard, ...) passes through
  " expand() unchanged, so it alone can't reveal that ':cd' moved us to a
  " different underlying file. Canonicalize to an absolute path (which
  " *does* incorporate the current working directory) for cache-keying.
  let abspath = fnamemodify(path, ':p')
  let ftime = filereadable(path) ? getftime(path) : -1
  if src.path !=# abspath || src.ftime !=# ftime
    let src.path = abspath
    let src.ftime = ftime
    let src.candidates = s:ReadCandidates(src.file)
  endif
  return src.candidates
endfunction

" Public API: register a named completion source backed by a plain-text
" file, bound to an insert-mode invocation (e.g. '<C-x><C-n>').
"
" call sgcomplete#Register('names', '~/.vim/completions/names.txt', '<C-x><C-n>')
function! sgcomplete#Register(name, file, map) abort
  if empty(a:name)
    call s:Warn('Register() called with an empty source name; ignoring')
    return
  endif
  if empty(a:map)
    call s:Warn('Register(''' . a:name . ''') called with an empty mapping; ignoring')
    return
  endif

  if !empty(maparg(a:map, 'i'))
    call s:Warn('mapping ' . a:map . ' already in use; skipping registration of source "'
          \ . a:name . '" (existing mappings are never overwritten)')
    return
  endif

  let s:sources[a:name] = {'file': a:file, 'map': a:map, 'path': '', 'ftime': -2, 'candidates': []}

  " complete() cannot be called from an <expr> mapping (textlock), so we
  " use the <C-r>=...<CR> idiom: the expression register evaluation runs
  " outside textlock, and sgcomplete#Complete() returns '' so nothing
  " extra is inserted.
  execute 'inoremap <silent> <unique> ' . a:map
        \ . ' <C-r>=sgcomplete#Complete(' . string(a:name) . ')<CR>'
endfunction

" Locate the start of the "word" immediately before the cursor: scan
" backwards from the cursor until whitespace or the start of the line.
function! s:PrefixStartCol(line, col) abort
  let start = a:col - 1
  while start > 0 && a:line[start - 1] !~# '\s'
    let start -= 1
  endwhile
  return start
endfunction

" Filter a source's candidates down to those starting with a:prefix.
" Comparison honors 'ignorecase', matching Vim's own completion behavior.
" Exposed publicly (rather than kept script-local) so it can be exercised
" directly by tests without needing a live Insert-mode popup.
function! sgcomplete#Matches(name, prefix) abort
  if !has_key(s:sources, a:name)
    call s:Warn('unknown source "' . a:name . '"')
    return []
  endif

  let candidates = s:GetCandidates(a:name)
  if empty(candidates)
    return []
  endif
  if empty(a:prefix)
    return copy(candidates)
  endif

  let matches = []
  for cand in candidates
    let candhead = strpart(cand, 0, strlen(a:prefix))
    if &ignorecase
      let matched = tolower(candhead) ==# tolower(a:prefix)
    else
      let matched = candhead ==# a:prefix
    endif
    if matched
      call add(matches, cand)
    endif
  endfor
  return matches
endfunction

" Invoked from the <expr> insert-mode mapping created in Register().
" Computes the prefix immediately before the cursor, filters this source's
" candidates, and starts native popup-menu completion via complete().
" Always returns '' so the mapping inserts nothing on its own.
function! sgcomplete#Complete(name) abort
  let line = getline('.')
  let col = col('.')
  let start = s:PrefixStartCol(line, col)
  let prefix = strpart(line, start, col - 1 - start)

  let matches = sgcomplete#Matches(a:name, prefix)
  if empty(matches)
    return ''
  endif

  call complete(start + 1, matches)
  return ''
endfunction

" Utility: list registered sources, e.g. for :SgCompleteSources.
function! sgcomplete#Sources() abort
  return copy(s:sources)
endfunction

" Utility: force cache invalidation for one source (omitted = all sources),
" e.g. for :SgCompleteReload.
function! sgcomplete#Reload(...) abort
  let name = get(a:000, 0, '')
  if empty(name)
    for src in values(s:sources)
      let src.ftime = -2
    endfor
    return
  endif
  if has_key(s:sources, name)
    let s:sources[name].ftime = -2
  endif
endfunction

" Test-only helper: drop all registrations so tests run in isolation.
function! sgcomplete#Reset() abort
  let s:sources = {}
endfunction
