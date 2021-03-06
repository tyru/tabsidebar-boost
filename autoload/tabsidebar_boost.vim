scriptencoding utf-8
let s:save_cpo = &cpo
set cpo&vim

if !has('tabsidebar')
  finish
endif

function! s:get_chars(default) abort
  if type(get(g:, 'tabsidebar_boost#chars')) !=# v:t_string
    return a:default
  endif
  if stridx(g:tabsidebar_boost#chars, "\t") !=# -1
    echohl ErrorMsg
    echomsg 'tabsidebar-boost: g:tabsidebar_boost#chars cannot contain tab character.'
    \       'using default value...'
    echohl None
    return a:default
  endif
  return g:tabsidebar_boost#chars
endfunction

let g:tabsidebar_boost#chars = s:get_chars('asdfghjklzxcvbnmqwertyuiop')
let g:tabsidebar_boost#format_window = get(g:, 'tabsidebar_boost#format_window', 'tabsidebar_boost#format_window')
let g:tabsidebar_boost#format_tabpage = get(g:, 'tabsidebar_boost#format_tabpage', 'tabsidebar_boost#format_tabpage')


function! tabsidebar_boost#format_window(win) abort
  let w = get(getwininfo(a:win.winid), 0, {})
  if empty(w)
    return ''
  endif
  let active = a:win.winid ==# win_getid() ? '>' : ' '
  let id = tabsidebar_boost#is_jumping() ? printf(' (%s)', a:win.char_id()) : ''
  let name = w.loclist ? '[Location List]' :
  \          w.quickfix ? '[Quickfix List]' :
  \          empty(bufname(w.bufnr)) ? printf('Buffer #%d', w.bufnr) :
  \          fnamemodify(bufname(w.bufnr), ':t')
  let flags = (!w.terminal && getbufvar(w.bufnr, '&modified') ? ['+'] : []) +
  \           (getbufvar(w.bufnr, '&readonly') ? ['RO'] : [])
  let flags_status = empty(flags) ? '' : ' [' . join(flags, ',') . ']'
  return printf(' %s%s %s%s', active, id, name, flags_status)
endfunction

function! tabsidebar_boost#format_tabpage(tabnr, winlines) abort
  let title = gettabvar(a:tabnr, 'tabsidebar_boost_title')
  if title ==# ''
    let title = printf('Tab #%d', a:tabnr)
  endif
  return join([title] + a:winlines, "\n")
endfunction

function! tabsidebar_boost#set_tab_title(title) abort
  let t:tabsidebar_boost_title = a:title
  call tabsidebar_boost#adjust_column()
endfunction

function! tabsidebar_boost#tabsidebar(tabnr) abort
  try
    let wininfo = s:get_wininfo(g:tabsidebar_boost#chars)
    let winlines = map(tabpagebuflist(a:tabnr), {winidx,bufnr ->
    \ call(g:tabsidebar_boost#format_window, [
    \   s:find_window(wininfo, {'winid': win_getid(winidx + 1, a:tabnr)})
    \ ])
    \})
    return call(g:tabsidebar_boost#format_tabpage, [a:tabnr, winlines])
  catch
    " Disable tabsidebar-boost display
    execute 'command! -bar TabSideBarBoostRestore let [&tabsidebar, g:tabsidebar_boost#auto_adjust_tabsidebarcolumns] = ' . string([&tabsidebar, g:tabsidebar_boost#auto_adjust_tabsidebarcolumns])
    set tabsidebar&
    let g:tabsidebar_boost#auto_adjust_tabsidebarcolumns = 0
    echohl ErrorMsg
    echomsg 'tabsidebar-boost: error occurred. disabled tabsidebar-boost.'
    echomsg '  ' . v:exception '@' v:throwpoint
    echomsg 'tabsidebar-boost: please run :TabSideBarBoostRestore to re-enable tabsidebar-boost'
    echohl None
  endtry
endfunction

function! tabsidebar_boost#adjust_column() abort
  if get(g:, 'tabsidebar_boost#auto_adjust_tabsidebarcolumns')
    try
      let &tabsidebarcolumns = tabsidebar_boost#get_max_column()
    catch /tabsidebar-boost: error occurred/
      let g:tabsidebar_boost#auto_adjust_tabsidebarcolumns = 0
      throw v:exception
    endtry
  endif
endfunction

function! tabsidebar_boost#get_max_column() abort
  let maxcol = 0
  for tabnr in range(1, tabpagenr('$'))
    for line in split(tabsidebar_boost#tabsidebar(tabnr), '\n')
      let maxcol = max([len(line), maxcol])
    endfor
  endfor
  return maxcol
endfunction

function! tabsidebar_boost#is_jumping() abort
  return s:is_jumping
endfunction

let s:is_jumping = 0

function! tabsidebar_boost#jump() abort
  let wininfo = s:get_wininfo(g:tabsidebar_boost#chars)
  let wins = s:search_windows(wininfo, {})
  let buf = ''
  let s:is_jumping = 1
  " Input characters until matching exactly or failing to match.
  try
    if get(g:, 'tabsidebar_boost#auto_adjust_tabsidebarcolumns')
      let &tabsidebarcolumns = tabsidebar_boost#get_max_column()
    endif
    redraw
    while 1
      echon "\rInput window character(s): " . buf
      let c = s:getchar()
      if c ==# "\<Esc>"
        redraw
        echo ''
        return
      endif
      let buf .= c
      if empty(filter(copy(wins), {_,w -> w.char_id() !=# buf && w.char_id() =~# '^' . buf }))
        break
      endif
    endwhile
  finally
    let s:is_jumping = 0
  endtry
  let win = get(filter(copy(wins), {_,w -> w.char_id() ==# buf }), 0, {})
  if empty(win)
    return
  endif
  call win_gotoid(win.winid)
endfunction

function! tabsidebar_boost#next_window() abort
  return s:next_window(v:count1, g:tabsidebar_boost#chars)
endfunction

function! tabsidebar_boost#previous_window() abort
  return s:next_window(-v:count1, g:tabsidebar_boost#chars)
endfunction

function! s:next_window(n, chars) abort
  let [wins, curidx] = s:get_windows_with_index(a:chars)
  if curidx ==# -1
    throw 'tabsidebar-boost: could not find current window'
  endif
  let win = wins[(curidx + a:n) % len(wins)]
  call win_gotoid(win.winid)
endfunction

function! s:get_windows_with_index(chars) abort
  let wininfo = s:get_wininfo(a:chars)
  let wins = s:search_windows(wininfo, {'order_by': function('s:by_id')})
  let curidx = -1
  let winid = win_getid()
  for i in range(len(wins))
    if wins[i].winid ==# winid
      let curidx = i
      break
    endif
  endfor
  return [wins, curidx]
endfunction

function! s:by_id(a, b) abort
  return s:asc(a:a.id, a:b.id)
endfunction

function! s:asc(a, b) abort
    return a:a > a:b ? 1 : a:a < a:b ? -1 : 0
endfunction

function! s:getchar(...) abort
  let c = call('getchar', a:000)
  return type(c) is# v:t_number ? nr2char(c) : c
endfunction

function! s:get_wininfo(chars) abort
  let wininfo = {'__chars__': a:chars}
  let id = 0
  for tabnr in range(1, tabpagenr('$'))
    let tab = get(gettabinfo(tabnr), 0, {})
    for winid in get(tab, 'windows', [])
      let wininfo[join([id, tabnr, winid], "\t")] = 1
      let id += 1
    endfor
  endfor
  let wininfo.__count__ = id
  return wininfo
endfunction

function! s:find_window(wininfo, conditions) abort
  return s:search_windows(a:wininfo, a:conditions)[0]
endfunction

function! s:search_windows(wininfo, conditions) abort
  let re = '^' . get(a:conditions, 'id', '[^\t]\+')
  \     . '\t' . get(a:conditions, 'tabnr', '[^\t]\+')
  \     . '\t' . get(a:conditions, 'winid', '[^\t]\+')
  \     . '$'
  let keys = filter(keys(a:wininfo), {_,key -> key =~# re})
  " Convert window strings to dictionary
  let wins = map(map(keys, {_,k -> split(k, '\t')}), {_,items -> {
  \ 'id': items[0] + 0,
  \ 'char_id': function('s:convert_id', [items[0] + 0, a:wininfo]),
  \ 'tabnr': items[1] + 0,
  \ 'winid': items[2] + 0,
  \}})
  return type(get(a:conditions, 'order_by')) ==# v:t_func ?
  \         sort(wins, a:conditions.order_by) : wins
endfunction

function! s:convert_id(n, wininfo) abort
  let chars = a:wininfo.__chars__
  let base = len(chars)
  let max_n = a:wininfo.__count__
  let digit = max_n <=# 0 ? 1 : float2nr(floor(log(max_n) / log(base) + 1))
  let n = a:n
  let id = ''
  for _ in range(digit)
    let id = chars[n % base] . id
    let n = n / base
  endfor
  return id
endfunction

let &cpo = s:save_cpo
