perl << .
use strict;
use lib "$ENV{HOME}/.vim/plugin";
use Search::Pattern 1.00;
use Search::Tags 1.00;
use Search::Complete 1.00;

$main::dbg = 0;

sub dprint() {
   $main::dbg = 0 unless defined $main::dbg;
   if ($main::dbg) {
      print "@_\n";
   }
}

# cannot run this routine with 'use strict'!
sub print_object() {
   my ($name) = @_;
   my $o = $$name;

   foreach my $key (sort keys %{$o}) {
      my $val = $o->{$key};
      $val = join "|", @{$val} if ($val =~ /ARRAY/);
      print "$name"."->{$key} = >$val<\n";
   }
}

sub _msg {
   my ($m, $hl) = @_;

   VIM::DoCommand("echohl ModeMsg");
   VIM::DoCommand("echon '-- Context completion (^J^K) '");
   VIM::DoCommand("echohl $hl");
   VIM::DoCommand("echon '$m\n'");
   VIM::DoCommand("echohl None");
}

sub msg {
   &_msg(shift, "Question");
}

sub error {
   &_msg(shift, "ErrorMsg");
}

sub warn {
   &_msg(shift, "WarningMsg");
}

sub find_variable_type() {
   my $line = shift;

   $line =~ s/[\*&]//g;
   $line =~ s/.*;\s*//g;
   $line =~ s/.*\(//;
   $line =~ s/\w+\s*,//g;
   my $pat = $main::pattern->ignore_keywords;
   $line =~ s/\b$pat\b//g;

   my ($ret) = ($line =~ /(\w[\w:]*)\s*$/);
   return $ret;
}

# returns an empty string if no type is found
sub find_local_type() {
   my $tag = $main::complete->tag;
   my $val = VIM::Eval("FindLocalVariableLine(\"$tag\")");
   $val = &find_variable_type($val);
   return $val;
}

sub find_tag_types() {
   my ($tag, $this) = @_;
   my (%types);

   &dprint("find_tag_types: looking in tags file for $tag");

   if ($this) {
      &dprint("find_tag_types: only looking at definitions found in class(es) $this!");
      $this =~ s/ /|/g;
      $this = "($this)";
   }
   elsif ($main::dbg) {
      print "find_tag_types: local class not provided, seaching for all matches\n";
   }

   $main::tags->binary_search($tag);

   LABEL: while ($_ = $main::tags->next_line) {
      &dprint("find_tag_types: looking at tag line: $_");
      if (/^($tag)\b/) {
         if (/c$/) {
            &dprint("find_tag_types: skipping class definition...");
         }
         elsif (!defined $this || /class:$this/) {
            my $def;
            if ($main::complete->is_method) {
               ($def) = $_ =~ /\/\^(.*)\$/;
               $def = $main::pattern->get_item($def, "%t");
            }
            elsif (/\/\^(.*)\b$tag\b/) {
               $def = &find_variable_type($1);
            }
            $types{$def} = 1 if ($def);
         }
      }
      else {
         last LABEL;
      }
   }

   return keys %types;
}

sub get_tag_types() {
   my $tag = shift;
   my @supers;

   unless ($tag eq "this" || $tag eq "super" || $main::complete->is_method) {
      # first look for a local definition of this tag
      my $type = &find_local_type();
      &dprint("get_tag_types: got local type >$type<");
      return $type if ($type);
   }

   my $this;
   unless ($main::complete->is_method) {
      &dprint("get_tag_types: looking for 'this' class...");
      $this = &find_this_class();

      return $this if ($tag =~ /(this|super)/);
   }

   &dprint("get_tag_types: looking for $tag in tags file...");
   my @types = &find_tag_types($tag, $this);
   push @types, $tag unless ($main::complete->is_method); # tag could be a static variable

   &dprint("get_tag_types: returning @types");
   return "@types";
}

sub _extract_member() {
   my ($line, $fullpat) = @_;
   my $val;

   # find a complete function
   if ($line =~ /($fullpat\s*\(.*?\))/) {
      $val = $1;
   }
   # find a partial function
   elsif ($line =~ /($fullpat\s*\(.*)\$/) {
      $val = "$1" .  &find_rest_of_prototype($line);
   }
   # find a variable
   else {
      $val = $fullpat;
   }
   $val =~ s/\s+/ /g;
   $val =~ s/\s\(/(/;
   return $val;
}

sub get_members_of_type() {
   my $classes = shift;

   my $pat = $main::complete->pat;
   &dprint("get_members_of_type: looking for pat>$pat< in classes>$classes<");

   my (%members);
   if ($pat) {
      # do a binary search through the tags file
      my $p = $pat;
      $p =~ s/\(//;

      $main::tags->binary_search($p);

      $classes =~ s/ /|/g;
      $classes = "($classes)";
      $pat =~ s/\(/\\b/;
      LABEL: while ($_ = $main::tags->next_line) {
         if (/^($pat\w*)/) {
            my $fullpat = $1;
            if (/:$classes/)
            {
               my $val = &_extract_member($_, $fullpat);
               $members{$val} = 1;
            }
         }
         else {
            last LABEL;
         }
      }
   }
   else {
      # find all members of this object... search through the cache
      # file instead
      my @class = split / /, $classes;
      while (my $c = shift @class) {
         $main::cache->binary_search($c);
         LABEL: while ($_ = $main::cache->next_line) {
            if (/^$c (\w+)/) {
               my $val = &_extract_member($_, $1);
               $members{$val} = 1;
            }
            else {
               last LABEL;
            }
         }
      }
   }
   my @members = sort keys %members;
   &dprint("get_members_of_type: found members: ".join "|", @members);
   $main::complete->clear_members;
   $main::complete->members(@members);
}

sub find_rest_of_prototype() {
   my $line = shift;
   my $tagfile = $main::tags->filename;

   my ($file) = $line =~ /(\S+)\s+\/\^/;

   if ($file !~ /^\//) {
      # this isn't an absolute path
      $file = "$tagfile$file";
      $file =~ s/tags//;
   }
   if (!-r $file) {
      &error("Cannot find file $file");
      return "";
   }

   $line =~ /\/\^(.+)\$/;
   my $searchpat = quotemeta $1;
   my $keeplooking = 0;
   my $rest = "";
   open(SOURCEFILE, $file);
   while (<SOURCEFILE>) {
      if (/^$searchpat$/) {
         $keeplooking = 1;
      }
      elsif ($keeplooking) {
         if (/\)/) {
            s/\s+(\w*.*\)).*/$1/;
            chomp;
            $rest .= " $_";
            last;
         }
         else {
            s/\s+(\w+.*,?).*/$1/;
            chomp;
            $rest .= " $_";
         }
      }
   }
   close SOURCEFILE;
   return $rest;
}

sub find_super_classes() {
   my $class = shift;
   my ($super, @supers);

   my $t = $main::tags->filename;
   my $c = $main::cache->filename;
   do {
      undef $super;
      $main::tags->binary_search($class);

      LABEL: while ($_ = $main::tags->next_line) {
         if (/^$class\b/) {
            if (/c$/)
            {
               my ($stop, $val) = $main::pattern->get_item($_, "%s");
               if ($stop) {
                  last LABEL;
               }
               elsif ($val) {
                  $super = $val;
                  push @supers, $val;
                  $class = $val;
                  last LABEL;
               }
            }
         }
         else {
            last LABEL;
         }
      }
   } while ($super);

   return @supers;
}

sub do_next_entry() {
   my $direction = shift;
   my $next_type;
   if ($direction == 0 || $main::complete->members == 0) {
      $next_type = $main::complete->next_type;

      &get_members_of_type($next_type);

      if ($main::complete->members == 0)
      {
         # &error("Pattern not found");
         &error("No members found for $next_type");
         &leave_in_insert_mode();
         return;
      }
   }
   my $newline = $main::complete->next_completion($direction, $main::curwin->Cursor());
   if ($newline) {
      my ($lnum, $col) = $main::complete->spot;

      $main::curbuf->Set($lnum, $newline);
      $main::curwin->Cursor($lnum, $col);

      my $item = $main::complete->memberindex;
      my $total = $main::complete->members - 1;
      if ($next_type) {
         $next_type =~ s/ /<-/g;
         &msg("type $next_type");
      }
      elsif ($item == 0) {
         &warn("Back at original");
      }
      else {
         &msg("match $item of $total");
      }
   }

   # &print_object("main::complete");
   # &print_object("main::pattern");

   &leave_in_insert_mode();
}

sub leave_in_insert_mode() {
   my ($linenum, $col) = $main::curwin->Cursor();
   my $line = $main::curbuf->Get($linenum);

   if (length $line == $col+1) {
      VIM::DoCommand("startinsert!");
   }
   else {
      VIM::DoCommand("normal l");
      VIM::DoCommand("startinsert");
   }
}

sub find_this_class() {
   my ($stop, $val);
   my ($linenum, $col) = $main::curwin->Cursor();
   LABEL: while ($linenum > 0) {
      my $line = $main::curbuf->Get($linenum);

      &dprint("find_this_class: looking at line:$line");
      ($stop, $val) = $main::pattern->get_item($line, "%c");
      if ($stop) {
         return undef;
      }
      elsif ($val) {
         return $val;
      }
   }
   continue {
      $linenum -= 1;
   }
   return undef;
}

sub create_cache_file {
   my $cache = shift;
   open(H, "| sort > $cache") or die "Can't open cache file $cache! $!\n";

   &msg("Updating tag cache file. Please wait...");
   $main::tags->reset;
   my $fn = $main::tags->filename;
   while ($_ = $main::tags->next_line) {
      if (/\s\w\s+class:/) {
         s/(.*)\s+\w\s+class:(\S+)/$2 $1/;
         print H;
      }
   }

   close H;
}

sub remap_esc {
   VIM::DoCommand("inoremap <silent> <ESC> <ESC>:perl -w &esc_pressed<cr>");
}

sub esc_pressed {
   $main::complete->leave_complete_mode;
   VIM::DoCommand("iunmap <silent> <ESC>");
}

sub setup_tags_file {
   my $setting = VIM::Eval("&tags");
   my $tagsfile = Search::Tags->get_tags_file($setting);
   unless ($tagsfile) {
      &error("No tags file found!");
      &leave_in_insert_mode();
      return 0;
   }
   if (defined $main::tag_objects{$tagsfile}) {
      $main::tags = $main::tag_objects{$tagsfile};
      $main::cache = $main::cache_objects{$tagsfile};

      if ($main::tags->check_for_updates) {
         &create_cache_file($main::cache->filename);
         $main::cache->check_for_updates;
      }
   }
   else {
      $main::tags = Search::Tags->new($tagsfile);
      $main::tag_objects{$tagsfile} = $main::tags;

      my $cache = "$tagsfile.cache";

      if (not -e $cache) {
         &create_cache_file($cache);
      }
      else {
         my (@info) = stat $cache;
         my $cache_mtime = $info[9];

         my $tag_mtime = $main::tags->mtime;

         if ($tag_mtime > $cache_mtime) {
            &create_cache_file($cache);
         }
      }

      $main::cache = Search::Tags->new($cache);
      $main::cache_objects{$tagsfile} = $main::cache;
   }
   # &print_object("main::tags");
   # &print_object("main::cache");
   return 1;
}

sub setup_search_patterns {
   my $ok = VIM::Eval("exists('b:ContextCompleteSearchPattern')");
   my $pat;
   if ($ok) {
      $pat = VIM::Eval("b:ContextCompleteSearchPattern");
   }
   $ok = VIM::Eval("exists('b:ContextCompleteIgnoreKeywords')");
   my $ignore;
   if ($ok) {
      $ignore = VIM::Eval("b:ContextCompleteIgnoreKeywords");
   }
   $main::pattern = Search::Pattern->new($pat, $ignore); # ok if params are undef
   # &print_object("main::pattern");
}

sub setup_tags {
   my $tag = $main::complete->tag;
   my $all = &get_tag_types($tag);
   unless ($all) {
      &error("No types found for $tag!");
      &leave_in_insert_mode();
      return 0;
   }

   my @all = split / /, $all;
   foreach my $t (@all) {
      my @supers = &find_super_classes($t);
      if (@supers) {
         $t = (($tag eq "super") ? "" : "$t " ) . "@supers";
      }
   }

   $main::complete->types(@all);
   &dprint("context_complete: found these types: @all");
   return 1;
}

sub next_type() { 
   context_complete(0);
}

sub next_match {
   context_complete(1);
}

sub prev_match {
   context_complete(-1);
}

sub context_complete() {
   my ($dir) = @_;
   my (@pos) = $main::curwin->Cursor();
   if ($main::complete && $main::complete->in_complete_mode(@pos)) {
      &dprint("context_complete: already in complete mode...");
      &do_next_entry($dir);
      return;
   }

   my $line = $main::curbuf->Get($pos[0]);
   $main::complete = Search::Complete->new(@pos, $line);

   # do this every time because the 'tags' setting can change anytime
   # without notice
   &setup_tags_file or return;

   # also do this every time because the buffer filetype can easily change
   &setup_search_patterns;

   &remap_esc;

   &setup_tags or return;

   &do_next_entry($dir);
}
.

" vim: fdm=indent:sw=3:ts=3:fdi=

