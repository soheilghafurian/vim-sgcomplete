" test/test_sgcomplete.vim
" Self-contained Vim test suite for vim-sgcomplete. Run via test/run_tests.sh.
" Uses assert_equal/assert_true (accumulating into v:errors) plus a light
" Insert-mode integration check via feedkeys() for end-to-end behavior.

let s:here = expand('<sfile>:h')
let s:fixtures = s:here . '/completions'

" ---------------------------------------------------------------------------
" Fixtures
let s:names_file = s:fixtures . '/names.txt'         " John Smith / Jane Doe / (blank) / Jordan Lee
let s:companies_file = s:fixtures . '/companies.txt' " Acme Corp / Acme Industries / Globex Corporation
let s:empty_file = s:fixtures . '/empty.txt'
let s:missing_file = s:fixtures . '/does-not-exist.txt'

call sgcomplete#Reset()
call sgcomplete#Register('names', s:names_file, '<Plug>(TestNames)')
call sgcomplete#Register('companies', s:companies_file, '<Plug>(TestCompanies)')
call sgcomplete#Register('emptysrc', s:empty_file, '<Plug>(TestEmpty)')
call sgcomplete#Register('missingsrc', s:missing_file, '<Plug>(TestMissing)')

" ---------------------------------------------------------------------------
" 1. Multiple independent sources: each only surfaces its own candidates.
call assert_equal(['John Smith', 'Jane Doe', 'Jordan Lee'], sgcomplete#Matches('names', ''))
call assert_equal(['Acme Corp', 'Acme Industries', 'Globex Corporation'], sgcomplete#Matches('companies', ''))

" Invoking one source never returns candidates belonging to another.
for m in sgcomplete#Matches('companies', '')
  call assert_true(index(sgcomplete#Matches('names', ''), m) == -1,
        \ 'companies candidate "' . m . '" leaked into names source')
endfor

" ---------------------------------------------------------------------------
" 2. Prefix filtering
call assert_equal(['John Smith', 'Jordan Lee'], sgcomplete#Matches('names', 'Jo'))
call assert_equal(['Jane Doe'], sgcomplete#Matches('names', 'Ja'))
call assert_equal([], sgcomplete#Matches('names', 'Zzz'))
call assert_equal(['Acme Corp', 'Acme Industries'], sgcomplete#Matches('companies', 'Acme'))

" ---------------------------------------------------------------------------
" 3. Entries containing spaces are preserved whole as single candidates.
call assert_true(index(sgcomplete#Matches('names', 'John'), 'John Smith') >= 0)
call assert_equal(['John Smith'], sgcomplete#Matches('names', 'John'))

" ---------------------------------------------------------------------------
" 4. Blank lines in completion files are ignored.
call assert_true(index(sgcomplete#Matches('names', ''), '') == -1, 'blank line leaked into candidates')
call assert_equal(3, len(sgcomplete#Matches('names', '')))

" ---------------------------------------------------------------------------
" 5. Missing / unreadable / empty files degrade gracefully to no candidates.
call assert_equal([], sgcomplete#Matches('emptysrc', ''))
call assert_equal([], sgcomplete#Matches('missingsrc', ''))
call assert_equal([], sgcomplete#Matches('missingsrc', 'anything'))

" Also: an entirely unknown source name must not error, just yield nothing.
call assert_equal([], sgcomplete#Matches('no-such-source', ''))

" ---------------------------------------------------------------------------
" 6. Registration must not overwrite an existing mapping.
inoremap <Plug>(PreExisting) <Nop>
let s:preexisting_rhs_before = maparg('<Plug>(PreExisting)', 'i')
call sgcomplete#Register('shouldnotwin', s:names_file, '<Plug>(PreExisting)')
call assert_equal(s:preexisting_rhs_before, maparg('<Plug>(PreExisting)', 'i'),
      \ 'sgcomplete#Register() overwrote a pre-existing mapping')
" and the source itself must not have been registered either.
call assert_equal([], sgcomplete#Matches('shouldnotwin', ''))

" ---------------------------------------------------------------------------
" 7. ignorecase honored the same way Vim's own completion honors it.
set ignorecase
call assert_equal(['John Smith', 'Jordan Lee'], sgcomplete#Matches('names', 'jo'))
set noignorecase
call assert_equal([], sgcomplete#Matches('names', 'jo'))

" ---------------------------------------------------------------------------
" 8. End-to-end Insert-mode integration: invoking the mapping opens the
" popup with the right candidates, and selecting one inserts the full
" (space-containing) value into the buffer.
"
" Note: feedkeys() with the 'x' flag only reflects intermediate Insert-mode
"/popup state (pumvisible(), complete_info()) while it is still executing;
" once control returns to this script, Vim has implicitly left Insert mode
" to run further Ex commands, closing the popup. So each scenario below is
" driven end-to-end in a single feedkeys() call and verified by the
" resulting buffer text rather than by polling popup state mid-flight.
new
call sgcomplete#Register('e2enames', s:names_file, '<F2>')
call sgcomplete#Register('e2ecompanies', s:companies_file, '<F3>')

" First match ("John Smith") accepted directly.
call setline(1, '')
call feedkeys("i" . 'Jo' . "\<F2>" . "\<C-y>\<Esc>", 'xt')
call assert_equal('John Smith', getline(1),
      \ 'selecting the first candidate should insert its full (space-containing) value')

" Cycle to the second match ("Jordan Lee") within the SAME source.
call setline(1, '')
call feedkeys("i" . 'Jo' . "\<F2>" . "\<C-n>\<C-y>\<Esc>", 'xt')
call assert_equal('Jordan Lee', getline(1),
      \ 'cycling within a source should only reach that source''s own candidates')

" A different source's invocation on the same buffer never offers "names"
" candidates: "Ac" only matches company entries.
call setline(1, '')
call feedkeys("i" . 'Ac' . "\<F3>" . "\<C-y>\<Esc>", 'xt')
call assert_equal('Acme Corp', getline(1),
      \ 'companies source should surface its own candidate, not a names candidate')

bwipeout!

" ---------------------------------------------------------------------------
let s:result_file = $SGCOMPLETE_TEST_OUT
if len(v:errors) == 0
  call writefile(['ALL TESTS PASSED'], s:result_file)
  qa!
else
  call writefile(['TEST FAILURES:'] + v:errors, s:result_file)
  cquit 1
endif
