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
" 7. g:sgcomplete_ignorecase controls case-sensitivity, independently of
" Vim's own 'ignorecase' (which stays untouched, so search etc. are
" unaffected). Default (unset) is case-insensitive.
set noignorecase
call assert_equal(['John Smith', 'Jordan Lee'], sgcomplete#Matches('names', 'jo'),
      \ 'default (g:sgcomplete_ignorecase unset) should be case-insensitive regardless of &ignorecase')

let g:sgcomplete_ignorecase = 0
call assert_equal([], sgcomplete#Matches('names', 'jo'),
      \ 'g:sgcomplete_ignorecase = 0 should make matching case-sensitive, even though &ignorecase is off'
      \ . ' (i.e. unrelated to &ignorecase either way)')
call assert_equal(['John Smith', 'Jordan Lee'], sgcomplete#Matches('names', 'Jo'))

" The exact scenario this option exists for: completion case-insensitive
" while search/etc. (&ignorecase) stays case-sensitive, untouched.
let g:sgcomplete_ignorecase = 1
call assert_equal(0, &ignorecase, 'sanity: &ignorecase must still be off here')
call assert_equal(['John Smith', 'Jordan Lee'], sgcomplete#Matches('names', 'jo'),
      \ 'g:sgcomplete_ignorecase = 1 should be case-insensitive even with &ignorecase off')
unlet g:sgcomplete_ignorecase

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
" 9. Per-project sources: a single registration with a *relative* path
" must serve different content depending on Vim's current working
" directory, including a ':cd' mid-session (no restart needed) -- and
" must not be fooled into serving stale, wrong-project candidates when
" the two backing files happen to share an mtime (regression: caching
" keyed on mtime alone, without the resolved path, served project A's
" cached candidates for project B after 'cd' whenever both files'
" mtimes coincided).
let s:orig_cwd = getcwd()
let s:cwd_a = s:fixtures . '/cwd-a'
let s:cwd_b = s:fixtures . '/cwd-b'
" Force identical mtimes so this test actually exercises the mtime-collision
" case rather than accidentally passing because the mtimes happened to differ.
call system('touch -t 202501010000 ' . shellescape(s:cwd_a . '/slot1.txt')
      \ . ' ' . shellescape(s:cwd_b . '/slot1.txt'))

execute 'cd ' . fnameescape(s:cwd_a)
call sgcomplete#Register('cwdslot', 'slot1.txt', '<F6>')
call assert_equal(['Alice'], sgcomplete#Matches('cwdslot', ''),
      \ 'relative-path source should serve project A''s file when cwd is project A')

execute 'cd ' . fnameescape(s:cwd_b)
call assert_equal(['Bob'], sgcomplete#Matches('cwdslot', ''),
      \ 'relative-path source should serve project B''s file after :cd, even with a matching mtime')

execute 'cd ' . fnameescape(s:orig_cwd)

" ---------------------------------------------------------------------------
let s:result_file = $SGCOMPLETE_TEST_OUT
if len(v:errors) == 0
  call writefile(['ALL TESTS PASSED'], s:result_file)
  qa!
else
  call writefile(['TEST FAILURES:'] + v:errors, s:result_file)
  cquit 1
endif
