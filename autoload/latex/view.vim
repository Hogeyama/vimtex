" LaTeX plugin for Vim
"
" Maintainer: Karl Yngve Lervåg
" Email:      karl.yngve@gmail.com
"

function! latex#view#init(initialized) " {{{1
  call latex#util#set_default('g:latex_view_enabled', 1)
  if !g:latex_view_enabled | return | endif

  let data = g:latex#data[b:latex.id]

  " Initialize viewer options
  for viewer in s:viewers
    call latex#util#set_default('g:latex_view_' . viewer . '_options', '')
  endfor

  " Initialize other options
  call latex#util#set_default_os_specific('g:latex_view_general_viewer',
        \ {
        \   'linux' : 'xdg-open',
        \   'mac'   : 'open',
        \ })
  call latex#util#set_default('g:latex_view_method', 'general')
  call latex#util#set_default('g:latex_view_mupdf_send_keys', '')
  call latex#util#error_deprecated('g:latex_viewer')

  let viewer = 's:' . g:latex_view_method
  if !exists(viewer)
    echoerr "Viewer does not exist!"
    echoerr "Viewer: " . g:latex_view_method
    return
  endif

  execute 'let data.viewer = ' . viewer
  call data.viewer.init()

  " Define commands
  command! -buffer VimLatexView call g:latex#data[b:latex.id].viewer.view()
  if has_key(data.viewer, 'reverse_search')
    command! -buffer -nargs=* VimLatexRSearch
          \ call g:latex#data[b:latex.id].viewer.reverse_search()
  endif

  " Define mappings
  nnoremap <buffer> <plug>(vl-view)
        \ :call g:latex#data[b:latex.id].viewer.view()<cr>
  if has_key(data.viewer, 'reverse_search')
    nnoremap <buffer> <plug>(vl-reverse-search)
          \ :call g:latex#data[b:latex.id].viewer.reverse_search()<cr>
  endif
endfunction

"}}}1

let s:viewers = [
      \ 'general',
      \ 'mupdf',
      \ 'okular',
      \ 'qpdfview',
      \ 'sumatrapdf',
      \ 'zathura',
      \ ]
for viewer in s:viewers
  execute 'let s:' . viewer . ' = {}'
endfor

" {{{1 General
function! s:general.init() dict "{{{2
  if !executable(g:latex_view_general_viewer)
    echoerr "General viewer is not available!"
    echoerr "g:latex_view_general_viewer = "
          \ . g:latex_view_general_viewer
  endif
endfunction

" }}}2
function! s:general.view() dict " {{{2
  let exe = {}
  let exe.cmd = g:latex_view_general_viewer

  let outfile = g:latex#data[b:latex.id].out()
  if !filereadable(outfile)
    echomsg "Can't view: Output file is not readable!"
    return
  endif
  let exe.cmd .= ' ' . g:latex_view_general_options
  let exe.cmd .= ' ' . latex#util#fnameescape(outfile)

  call latex#util#execute(exe)
  let g:latex#data[b:latex.id].cmds.view = exe.cmd
endfunction

" }}}2

" {{{1 MuPDF
function! s:mupdf.init() dict "{{{2
  if !executable('mupdf')
    echoerr "MuPDF is not available!"
  endif

  " Initialize X window ID
  let self.xwin_id = 0
endfunction

" }}}2
function! s:mupdf.view() dict "{{{2
  if !self.exists()
    call self.start()
  else
    call self.forward_search()
  endif
endfunction

" }}}2
function! s:mupdf.exists() dict "{{{2
  if !executable('xdotool') | return 0 | endif

  let cmd = 'xdotool search --class MuPDF'
  let xwin_ids = systemlist(cmd)
  for id in xwin_ids
    if id == self.xwin_id | return 1 | endif
  endfor

  return 0
endfunction

"}}}2
function! s:mupdf.start() dict "{{{2
  let outfile = g:latex#data[b:latex.id].out()
  if !filereadable(outfile)
    echomsg "Can't view: Output file is not readable!"
    return
  endif

  " Start MuPDF
  let exe = {}
  let exe.cmd  = 'mupdf ' .  g:latex_view_mupdf_options
  let exe.cmd .= ' ' . latex#util#fnameescape(outfile)
  call latex#util#execute(exe)
  let g:latex#data[b:latex.id].cmds.view = exe.cmd

  if !executable('xdotool') | return | endif

  " Get window id
  if self.xwin_id == 0
    let cmd = 'xdotool search --class MuPDF'
    let xwin_ids = systemlist(cmd)
    if len(xwin_ids) == 0
      echomsg "Couldn't find MuPDF window ID!"
      let self.xwin_id = 0
    else
      let self.xwin_id = xwin_ids[-1]
    endif
  endif

  " Send keys to mupdf
  if g:latex_view_mupdf_send_keys != ''
    let cmd  = 'xdotool key --window ' . self.xwin_id
    let cmd .= ' ' . g:latex_view_mupdf_send_keys
    call system(cmd)
  endif

  call self.forward_search()
endfunction

"}}}2
function! s:mupdf.forward_search() dict "{{{2
  if !executable('synctex') || !executable('xdotool') | return | endif

  let outfile = g:latex#data[b:latex.id].out()

  let self.synctex_cmd = "synctex view -i "
        \ . (line(".") + 1) . ":"
        \ . (col(".") + 1) . ":"
        \ . latex#util#fnameescape(expand("%:p"))
        \ . " -o " . latex#util#fnameescape(outfile)
        \ . " | grep -m1 'Page:' | sed 's/Page://' | tr -d '\n'"
  let self.synctex_page = system(self.synctex_cmd)

  if self.synctex_page > 0
    let exe = {}
    let exe.cmd  = 'xdotool'
    let exe.cmd .= ' type --window ' . self.xwin_id
    let exe.cmd .= ' "' . self.synctex_page . 'g"'
    call latex#util#execute(exe)
    let self.forward_search_cmd = exe.cmd
  endif
endfunction

"}}}2
function! s:mupdf.reverse_search() dict "{{{2
  if !self.exists()
    echomsg "Can't search backwards: Is the PDF file open?"
    return
  endif

  let outfile = g:latex#data[b:latex.id].out()

  " Get page number
  let self.cmd_getpage  = "xdotool getwindowname " . self.xwin_id
  let self.cmd_getpage .= " | sed 's:.* - \\([0-9]*\\)/.*:\\1:'"
  let self.cmd_getpage .= " | tr -d '\n'"
  let self.page = system(self.cmd_getpage)
  if self.page <= 0 | return | endif

  " Get file
  let self.cmd_getfile  = "synctex edit "
  let self.cmd_getfile .= "-o \"" . self.page . ":288:108:" . outfile . "\""
  let self.cmd_getfile .= "| grep 'Input:' | sed 's/Input://' "
  let self.cmd_getfile .= "| head -n1 | tr -d '\n' 2>/dev/null"
  let self.file = system(self.cmd_getfile)

  " Get line
  let self.cmd_getline  = "synctex edit "
  let self.cmd_getline .= "-o \"" . self.page . ":288:108:" . outfile . "\""
  let self.cmd_getline .= "| grep -m1 'Line:' | sed 's/Line://' "
  let self.cmd_getline .= "| head -n1 | tr -d '\n'"
  let self.line = system(self.cmd_getline)

  " Go to file and line
  silent exec "edit " . self.file
  if self.line > 0
    silent exec ":" . self.line
    " Unfold, move to top line to correspond to top pdf line, and go to end of
    " line in case the corresponding pdf line begins on previous pdf page.
    normal! zvztg_
  endif
endfunction

" }}}2
function! s:mupdf.latexmk_callback() dict "{{{2
  if !executable('xdotool') | return | endif

  " Get window id
  if self.xwin_id == 0
    let cmd = 'xdotool search --class MuPDF'
    let xwin_ids = systemlist(cmd)
    if len(xwin_ids) == 0
      echomsg "Couldn't find MuPDF window ID!"
      let self.xwin_id = 0
    else
      let self.xwin_id = xwin_ids[-1]
    endif
  endif

  " Send keys to mupdf
  if g:latex_view_mupdf_send_keys != ''
    let cmd  = 'xdotool key --window ' . self.xwin_id
    let cmd .= ' ' . g:latex_view_mupdf_send_keys
    call system(cmd)
  endif

  " Return focus to vim
  silent execute '!xdotool windowfocus ' . v:windowid

  call self.forward_search()
endfunction

"}}}2
function! s:mupdf.latexmk_append_argument() dict " {{{2
  let cmd  = latex#latexmk#add_option('new_viewer_always', '0')
  let cmd .= latex#latexmk#add_option('pdf_update_method', '2')
  let cmd .= latex#latexmk#add_option('pdf_update_signal', 'SIGHUP')
  let cmd .= latex#latexmk#add_option('pdf_previewer',
        \ 'start mupdf ' .  g:latex_view_mupdf_options)
  return cmd
endfunction

"}}}2

" {{{1 Okular
function! s:okular.init() dict "{{{2
  if !executable('okular')
    echoerr "okular is not available!"
  endif
endfunction

"}}}2
function! s:okular.view() dict "{{{2
  let outfile = g:latex#data[b:latex.id].out()
  if !filereadable(outfile)
    echomsg "Can't view: Output file is not readable!"
    return
  endif

  let exe = {}
  let exe.cmd = 'okular ' . g:latex_view_okular_options
  let exe.cmd .= ' --unique ' . latex#util#fnameescape(outfile)
  let exe.cmd .= '\#src:' . line('.') . latex#util#fnameescape(expand('%:p'))

  call latex#util#execute(exe)
  let g:latex#data[b:latex.id].cmds.view = exe.cmd
endfunction

" }}}2

" {{{1 qpdfview
function! s:qpdfview.init() dict "{{{2
  if !executable('qpdfview')
    echoerr "qpdfview is not available!"
  endif
endfunction

"}}}2
function! s:qpdfview.view() dict "{{{2
  let outfile = g:latex#data[b:latex.id].out()
  if !filereadable(outfile)
    echomsg "Can't view: Output file is not readable!"
    return
  endif

  let exe = {}
  let exe.cmd = 'qpdfview ' . g:latex_view_qpdfview_options
  let exe.cmd .= ' --unique ' . latex#util#fnameescape(outfile)
  let exe.cmd .= '\#src:' . latex#util#fnameescape(expand('%:p'))
  let exe.cmd .= ':' . line('.')
  let exe.cmd .= ':' . col('.')

  call latex#util#execute(exe)
  let g:latex#data[b:latex.id].cmds.view = exe.cmd
endfunction

" }}}2

" {{{1 SumatraPDF
function! s:sumatrapdf.init() dict "{{{2
  if !executable('SumatraPDF')
    echoerr "SumatraPDF is not available!"
  endif
endfunction

"}}}2
function! s:sumatrapdf.view() dict "{{{2
  let outfile = g:latex#data[b:latex.id].out()
  if !filereadable(outfile)
    echomsg "Can't view: Output file is not readable!"
    return
  endif

  let exe = {}
  let exe.cmd = 'SumatraPDF ' . g:latex_view_sumatrapdf_options
  let exe.cmd .= ' -forward-search ' . latex#util#fnameescape(expand('%:p'))
  let exe.cmd .= ' ' . line('.')
  let exe.cmd .= ' ' . latex#util#fnameescape(outfile)

  call latex#util#execute(exe)
  let g:latex#data[b:latex.id].cmds.view = exe.cmd
endfunction

" }}}2

" {{{1 Zathura
function! s:zathura.init() dict "{{{2
  if !executable('zathura')
    echoerr "Zathura is not available!"
  endif

  let self.xwin_id = 0
endfunction

" }}}2
function! s:zathura.view() dict "{{{2
  if !self.exists()
    call self.start()
  else
    call self.forward_search()
  endif
endfunction

" }}}2
function! s:zathura.exists() dict "{{{2
  if !executable('xdotool') | return 0 | endif

  let cmd = 'xdotool search --class Zathura'
  let xwin_ids = systemlist(cmd)
  for id in xwin_ids
    if id == self.xwin_id | return 1 | endif
  endfor

  return 0
endfunction

"}}}2
function! s:zathura.start() dict "{{{2
  let outfile = g:latex#data[b:latex.id].out()
  if !filereadable(outfile)
    echomsg "Can't view: Output file is not readable!"
    return
  endif

  let exe = {}
  let exe.cmd  = 'zathura ' .  g:latex_view_zathura_options
  let exe.cmd .= ' -x "' . exepath(v:progname)
        \ . ' --servername ' . v:servername
        \ . ' --remote +\%{line} \%{input}"'
  let exe.cmd .= ' ' . latex#util#fnameescape(outfile)
  call latex#util#execute(exe)
  let g:latex#data[b:latex.id].cmds.view = exe.cmd

  if !executable('xdotool') | return | endif

  " Get window id
  if self.xwin_id == 0
    let cmd = 'xdotool search --class Zathura'
    let xwin_ids = systemlist(cmd)
    if len(xwin_ids) == 0
      echomsg "Couldn't find Zathura window ID!"
      let self.xwin_id = 0
    else
      let self.xwin_id = xwin_ids[-1]
    endif
  endif

  call self.forward_search()
endfunction

" }}}2
function! s:zathura.forward_search() dict "{{{2
  let outfile = g:latex#data[b:latex.id].out()
  if !filereadable(outfile)
    echomsg "Can't view: Output file is not readable!"
    return
  endif

  let exe = {}
  let exe.cmd  = 'zathura --synctex-forward '
  let exe.cmd .= line(".")
  let exe.cmd .= ':' . col('.')
  let exe.cmd .= ':' . latex#util#fnameescape(expand('%:p'))
  let exe.cmd .= latex#util#fnameescape(outfile)
  call latex#util#execute(exe)
  let g:latex#data[b:latex.id].zathura_fsearch = exe.cmd
endfunction

" }}}2
function! s:zathura.latexmk_callback() dict "{{{2
  if !executable('xdotool') | return | endif

  " Get window id
  if self.xwin_id == 0
    let cmd = 'xdotool search --class Zathura'
    let xwin_ids = systemlist(cmd)
    if len(xwin_ids) == 0
      echomsg "Couldn't find Zathura window ID!"
      let self.xwin_id = 0
    else
      let self.xwin_id = xwin_ids[-1]
    endif
  endif

  " Return focus to vim
  silent execute '!xdotool windowfocus ' . v:windowid

  call self.forward_search()
endfunction

"}}}2
function! s:zathura.latexmk_append_argument() dict " {{{2
  let cmd  = latex#latexmk#add_option('new_viewer_always', '0')
  let cmd .= latex#latexmk#add_option('pdf_previewer',
        \ 'start zathura ' . g:latex_view_zathura_options
        \ . ' -x \"' . exepath(v:progname)
        \ . ' --servername ' . v:servername
        \ . ' --remote +\%{line} \%{input}\" \%S')

  return cmd
endfunction

"}}}2
"}}}1

" vim: fdm=marker sw=2
