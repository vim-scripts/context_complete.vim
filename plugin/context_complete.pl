perl << .
sub dprint() {
   $debugging = 0	unless defined $debugging;
   if ($debugging) {
      print "@_\n";
   }
}

sub get_tags_file() {
   my $tags = VIM::Eval("&tags");
   my @files = split(/,/, $tags);
   my $tagfile;
   while ($tagfile = shift @files) {
      return $tagfile if (-r $tagfile);
   }

   return "";
}

sub is_function_definition() {
   my ($line) = shift;
   return 1 if ($line =~ /^[\w\s]*(task|function)/); # a vera task/function
   return 1 if ($line =~ /^\w+\s+\w+::/); # a c++ function def
   return 1 if ($line =~ /^(\w+)::~?\1/); # a c++ constructor
   return 0;
}

sub find_definition() {
   my $line = shift;

   $line =~ s/[\*&]//g;
   $line =~ s/.*;\s*//g;
   $line =~ s/.*\(//;
   $line =~ s/\w+\s*,//g;
   $line =~ s/\breturn\b//;

   if ($line =~ /(\w[\w:]*)\s*$/) {
      return $1;
   }
   else {
      return undef;
   }
}

# returns an empty string if no type is found
sub find_local_type() {
   $before =~ /.*\b(\w+)/;
   my $tag = $1;
   my ($success, $val) = VIM::Eval("FindLocalVariableLine(\"$tag\")");

   $val = &find_definition($val);
   return $val;
}

sub find_tag_completions() {
   my ($file, $tag) = @_;
   my (%types);

   &dprint("find_tag_completions: looking in tags file for $tag");
   open(TAGSFILE, $file);
   seek TAGSFILE, 0, 2; # find EOF position
   my $max = tell(TAGSFILE);

   my $pos = &binary_search(0, $max, $tag, \&read_routine, TAGSFILE);
   seek TAGSFILE, $pos, 0;

   LABEL: while (<TAGSFILE>) {
      if (/^($tag)\b/) {
         if (/c$/) {
            &dprint("find_tag_completions: skipping class definition...");
         }
         elsif (/\/\^(.*)\b$tag\b.*\$/) {
            &dprint("find_tag_completions: calling find_definition($1)");
            my $def = &find_definition($1);
            if (defined $def)
            {
               &dprint("find_tag_completions: found def >$def<");
               $types{$def} = 1;
            }
         }
      }
      else {
         last LABEL;
      }
   }
   close TAGSFILE;

   return keys %types;
}

sub get_tag_types() {
   my ($file, $tag, $delim) = @_;
   my $supers;

   if ($delim =~ /::/)
   {
      @supers = &find_super_classes($file, $tag);
      $tag = "$tag @supers" unless ($#supers == -1);
      &dprint("get_tag_types: static var, returning: $tag");
      return $tag;
   }

   # first look for a local definition of this tag
   my $type = &find_local_type();
   if (defined $type)
   {
      @supers = &find_super_classes($file, $type);
      $type = "$type @supers" unless ($#supers == -1);
      &dprint("get_tag_types: found local type, returning $type");
      return $type;
   }
   &dprint("get_tag_types: looking for tag in tags file...");
   my @types = &find_tag_completions($file, $tag);
   foreach my $t (@types) {
      @supers = &find_super_classes($file, $t);
      $t = "$t @supers" unless ($#supers == -1);
   }
   &dprint("get_tag_types: returning @types");
   return @types;
}

sub get_members_of_class() {
   my ($file, $classes, $pat) = @_;

   $classes =~ s/ /|/g;
   $classes = "($classes)";
   &dprint("get_members_of_class: looking for pat:$pat. in classes:$classes.");

   my (%members);
   open(TAGSFILE, $file);
   if (length $pat == 0) {
      # find all members of this object... forced to do a linear search through
      # the entire file =(
      while (<TAGSFILE>) {
         if (/:$classes/)
         {
            # find a complete function
            if (/(\w+\s*\(.*\))/) {
               $members{$1} = 1;
            }
            # find a partial function
            elsif (/(\w+\s*\(.*)\$/) {
               $m = &find_rest_of_prototype($file, $_);
               $members{"$1$m"} = 1;
            }
            # find a variable
            elsif (/^(\w+)/) {
               $members{$1} = 1;
            }
         }
      }
   }
   else {
      # do a binary search
      seek TAGSFILE, 0, 2; # find EOF position
      my $max = tell(TAGSFILE);
      my $p = $pat;
      $p =~ s/\(//;

      my $pos = &binary_search(0, $max, $p, \&read_routine, TAGSFILE);
      seek TAGSFILE, $pos, 0;

      $pat =~ s/\(/\\b/;
      LABEL: while (<TAGSFILE>) {
         if (/^($pat\w*)/) {
            my $fullpat = $1;
            if (/:$classes/)
            {
               # find a complete function
               if (/($fullpat\w*\s*\(.*?\))/) {
                  $members{$1} = 1;
               }
               # find a partial function
               elsif (/($fullpat\w*\s*\(.*)/) {
                  $m = &find_rest_of_prototype($file, $_);
                  $members{"$1$m"} = 1;
               }
               # find a variable
               else {
                  $members{$fullpat} = 1;
               }
            }
         }
         else {
            last LABEL;
         }
      }
   }
   close TAGSFILE;
   my @members = keys %members;
   return sort @members;
}

sub find_rest_of_prototype() {
   my ($tagfile, $line) = @_;

   $line =~ /\w+\s+(\S+)/;
   my ($file) = $1;
   if ($file !~ /^\//) {
      # this isn't an absolute path
      $file = "$tagfile$file";
      $file =~ s/tags//;
   }
   if (!-r $file) {
      VIM::Msg("Cannot find file $file");
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

sub study_line() {
   my ($linenum, $col) = $curwin->Cursor();
   my $line = $curbuf->Get($linenum);
   my $after = substr($line, $col+1);
   $line = substr($line, 0, $col+1);

   my $before = $line;

   $line =~ s/^\s+//;
   $line =~ s/\s+$//;
   $line =~ s/\s+\(/(/;

   my @tags = split(/([\. \(]|->|::)/, $line);
   if ($debugging) {
      foreach (@tags) {
         print "study_line: split: $_\n";
      }
   }

   my ($pat, $tag);
   my $delim = "";
   if ($line =~ /(\.|->|::)$/)
   {
      # looking for all members of this tag
      $pat = "";
      $delim = pop @tags; # pop delim
      $tag = pop @tags;
   }
   elsif ($line =~ /(\.|->|::)/)
   {
      # looking for only members that start with the pattern after the . or ->
      $pat = quotemeta(pop @tags);
      if ($pat =~ /\(/) {
         # the full function name is provided, just provide options for the
         # parameter list
         $pat = pop @tags;
         $pat = "$pat(";
         $delim = pop @tags;
         $delim = "$delim\(";
         $tag = pop @tags;
         $before =~ s/(\.|->|::).*$/$1/;
      }
      else {
         $before =~ s/(\.|->|::)$pat\s*$/$1/;
         $delim = pop @tags;
         $tag = pop @tags;
      }
   }

   &dprint("study_line: lnum:$lnum,before:$before,after:$after,tag:$tag,pat:$pat,delim:$delim.");
   return ($linenum, $before, $after, $tag, $pat, $delim);
}

sub find_super_classes() {
   my ($file, $class) = @_;
   my ($super, @supers);

   open(TAGSFILE, $file) || die "can't open $file!\n";
   seek TAGSFILE, 0, 2; # find EOF position
   my $max = tell(TAGSFILE);

   do {
      $super = "";
      my $pos = &binary_search(0, $max, $class, \&read_routine, TAGSFILE);
      seek TAGSFILE, $pos, 0;
      LABEL: while (<TAGSFILE>) {
         if (/^$class\b/) {
            if (/c$/ && /^$class\b/ && /(public|private|protected|extends)\s+(\w+)/)
            {
               $super = $2;
               push @supers, $super;
               $class = $super;

               last LABEL;
            }
         }
         else {
            last LABEL;
         }
      }
   } while (length $super != 0);
   close TAGSFILE;

   return @supers;
}

# only compares the $target with the first word in the tag file.
sub read_routine() {
   my ($handle, $target, $pos) = @_;
   my ($compare, $newpos);

   my $line;
   if (defined $pos) {
      seek $handle, $pos, 0;
      $line = <$handle>; # assume the first line is garbage
   }
   $newpos = tell($handle);
   $line = <$handle>;

   $line =~ /(\S+)/;
   $line = $1;
   $compare = $target cmp $line;
   return ($compare, $newpos);
}

# this subroutine is lifted from the Search::Binary module
sub binary_search {
	my $posmin = shift;
	my $posmax = shift;
	my $target = shift;
	my $readfn = shift;
	my $handle = shift;
	my $smallblock = shift || 512;

	my ($x, $compare, $mid, $lastmid);
	my ($seeks, $reads);

	# assert $posmin <= $posmax

	$seeks = $reads = 0;
	$lastmid = int(($posmin + $posmax)/2)-1;
	while ($posmax - $posmin > $smallblock) {
		# assert: $posmin is the beginning of a record
		# and $target >= index value for that record 
		$seeks++;
		$x = int(($posmin + $posmax)/2);
		($compare, $mid) = &$readfn($handle, $target, $x);
		unless (defined($compare)) {
			$posmax = $mid;
         next;
      }
      last if ($mid == $lastmid);
      if ($compare > 0) {
         $posmin = $mid;
      } else {
         $posmax = $mid;
      }
      $lastmid = $mid;
	}

	# Switch to sequential search.

	$x = $posmin;
	while ($posmin <= $posmax) {

		# same loop invarient as above applies here

		$reads++;
		($compare, $posmin) = &$readfn($handle, $target, $x);
		last unless (defined($compare) && $compare > 0);
		$x = undef;
	}
	wantarray ? ($posmin, $seeks, $reads) : $posmin;
}

sub in_complete_mode() {
   my $start = shift;

   unless (defined $complete_mode) {
      $complete_mode = $start;
      return $complete_mode;
   }
   if ($complete_mode == 0) {
      return $complete_mode;
   }

   my ($l, $c) = $curwin->Cursor();
   if ($l == $lnum && $c == $col) {
      $complete_mode = 1;
   }
   elsif ($col == -1) {
      $complete_mode = 0;
   }
   else {
      $complete_mode = 0;
   }
   return $complete_mode;
}

sub do_next_entry() {
   my $direction = shift;
   if ($direction =~ /F/) {
      $memberindex = 0;
      $complete_mode = 1;
   }
   elsif ($direction =~ /N/) {
      if (&in_complete_mode(0)) {
         $memberindex++;
         $memberindex = 0 if ($memberindex > $#members);
      }
      else {
         &leave_in_insert_mode();
         return;
      }
   }
   elsif ($direction =~ /P/) {
      if (&in_complete_mode(0)) {
         $memberindex--;
         $memberindex = $#members if ($memberindex < 0);
      }
      else {
         &leave_in_insert_mode();
         return;
      }
   }

   my $newline = "$before$members[$memberindex]";
   $col = (length $newline) - 1;
   $newline .= $after;

   $curbuf->Set($lnum, $newline);
   $curwin->Cursor($lnum,$col);
   &leave_in_insert_mode();
}

sub leave_in_insert_mode() {
   my ($linenum, $col) = $curwin->Cursor();
   my $line = $curbuf->Get($linenum);

   if (length $line == $col+1) {
      VIM::DoCommand("startinsert!");
   }
   else {
      VIM::DoCommand("normal l");
      VIM::DoCommand("startinsert");
   }
}

sub use_next_tag() { 
   $typeindex++;
   $typeindex = 0 if ($typeindex > $#types);

   @members = &get_members_of_class($tagsfile, $types[$typeindex], $pat);
   my $found = $#types + 1;
   my $index = $typeindex + 1;
   if ($#members == -1)
   {
      VIM::Msg("No members for type: $types[$typeindex]. ($index of $found definitions)");
      &leave_in_insert_mode();
      return;
   }
   my $t = $types[$typeindex];
   $t =~ s/ /<-/g;
   VIM::Msg("members for type: $t. ($index of $found definitions)");

   push @members, $pat;
   &do_next_entry("F");
}

sub context_complete() {
   $debugging = 0;
   ($lnum, $before, $after, $tag, $pat, $delim) = &study_line();

   if (length $delim == 0)
   {
      &leave_in_insert_mode();
      return;
   }

   $col = -1 unless (defined $col);
   if (&in_complete_mode(0)) {
      &dprint("context_complete: already in complete mode...");
      &do_next_entry("N");
      return;
   }

   $tagsfile = &get_tags_file;
   if (length $tagsfile == 0) {
      VIM::Msg("No tags file found!");
      &leave_in_insert_mode();
      return;
   }

   @types = &get_tag_types($tagsfile, $tag, $delim);
   if ($#types == -1) {
      VIM::Msg("No definition found for variable $tag!");
      &leave_in_insert_mode();
      return;
   }
   &dprint("context_complete: found these types: @types");

   $typeindex = -1;
   &use_next_tag();
}
.

" vim: fdm=indent:sw=3:ts=3
