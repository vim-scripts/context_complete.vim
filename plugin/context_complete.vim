" Author: Dave Eggum (deggum@synopsys.com)
" Version: 0.5

" See ":help context_complete.txt" for documentation

inoremap <silent> <C-Q> <ESC>:perl -w &context_complete()<cr>
inoremap <silent> <C-J> <ESC>:perl -w &do_next_entry("N")<cr>
inoremap <silent> <C-K> <ESC>:perl -w &do_next_entry("P")<cr>
inoremap <silent> <C-L> <ESC>:perl -w &use_next_tag()<cr>

source $HOME/.vim/plugin/context_complete.pl

function! FindLocalVariableLine(tag)
   set lazyredraw

   let searchcol = match(getline("."), a:tag."") + 1

   " save the current spot
   let linenum = line(".")
   let col = col(".")

   " find the topline in order to restore the cursor position relative to the
   " screen
   normal H
   let topline = line(".")

   " Use vim's "godo local declaration" feature (gd) and determine the variable type
   call cursor(linenum, searchcol)
   " gd bells when it fails... so turn the bell off first
   let savevb = &vb
   let savet_vb = &t_vb
   set vb t_vb=
   normal gd
   let &vb = savevb
   let &t_vb = savet_vb

   let l = line(".")
   let c = col(".")
   " echom l "==" linenum "," c "==" searchcol
   if (l == linenum && c == searchcol)
      " gd failed
      let line = ""
   else
      let line = getline(".")
      let line = strpart(line, 0, c-1)
   endif

   " restore the cursor and screen positions
   call cursor(topline, 0)
   normal zt

   " restore the cursor to the starting position
   call cursor(linenum, col)
   set nolazyredraw
   return line
endfunction

" returns the line and column number, and the result of the command, if any
function! InvisibleMotion(assign_result)
   " save the current spot
   let linenum = line(".")
   let col = col(".")
   set lazyredraw

   " save the current spot
   let linenum = line(".")
   let col = col(".")

   " find the topline in order to restore the cursor position relative to the
   " screen
   normal H
   let topline = line(".")
   call cursor(linenum, col)

   " echom "context_complete_motion_command:" g:context_complete_motion_command
   if (a:assign_result)
      exec "let result = ".g:context_complete_motion_command
   else
      exec g:context_complete_motion_command
      let result = ""
   endif

   let l = line(".")
   let c = col(".")

   " restore the cursor and screen positions
   call cursor(topline, 0)
   normal zt

   " restore the cursor to the starting position
   call cursor(linenum, col)
   set nolazyredraw

   return l.",".c.":".result
endfunction
   " :map [[ ?{<CR>w99[{

" vim: fdm=indent:sw=3:ts=3
