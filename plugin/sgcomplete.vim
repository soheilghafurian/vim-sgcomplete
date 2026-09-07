" plugin/sgcomplete.vim
" File-backed autocomplete sources for Vim.
" See doc/sgcomplete.txt for full documentation.

if exists('g:loaded_sgcomplete')
  finish
endif
let g:loaded_sgcomplete = 1

" Declarative registration: users may set g:sgcomplete_sources instead of
" (or in addition to) calling sgcomplete#Register() directly, e.g.:
"
"   let g:sgcomplete_sources = [
"         \ {'name': 'names',     'file': '~/.vim/completions/names.txt',     'map': '<C-x><C-n>'},
"         \ {'name': 'companies', 'file': '~/.vim/completions/companies.txt', 'map': '<C-x><C-c>'},
"         \ ]
"
" This must run after the user's vimrc has set g:sgcomplete_sources, so it
" is wrapped in an autocommand rather than executed at source time.
augroup sgcomplete
  autocmd!
  autocmd VimEnter * call s:RegisterConfiguredSources()
augroup END

function! s:RegisterConfiguredSources() abort
  for src in get(g:, 'sgcomplete_sources', [])
    if !has_key(src, 'name') || !has_key(src, 'file') || !has_key(src, 'map')
      echohl WarningMsg
      echom '[sgcomplete] g:sgcomplete_sources entry missing name/file/map: ' . string(src)
      echohl None
      continue
    endif
    call sgcomplete#Register(src.name, src.file, src.map)
  endfor
endfunction

command! SgCompleteSources call s:PrintSources()
command! -nargs=? SgCompleteReload call sgcomplete#Reload(<q-args>)

function! s:PrintSources() abort
  let sources = sgcomplete#Sources()
  if empty(sources)
    echom '[sgcomplete] no sources registered'
    return
  endif
  for [name, src] in items(sources)
    echom printf('[sgcomplete] %s -> %s (%s)', name, src.map, expand(src.file))
  endfor
endfunction
