perl << .
# use strict;

%gbl;

$gbl{DBG} = 0;

sub dprint() {
   $gbl{DBG} = 0 unless defined $gbl{DBG};
   if ($gbl{DBG}) {
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

sub get_function_definition() {
   my ($line) = shift;
   return $2 if ($line =~ /^[\w\s]*(task|function).*?(\w+)::/); # a vera task/function
   return $1 if ($line =~ /^\w+\s+(\w+)::/); # a c++ function def
   return $1 if ($line =~ /^(\w+)::~?\1/); # a c++ constructor
   return undef;
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
   my($tag) = $gbl{BEFORE} =~ /.*\b(\w+)/;
   my $val = VIM::Eval("FindLocalVariableLine(\"$tag\")");
   $val = &find_definition($val);
   return $val;
}

sub find_tag_types() {
   my ($file, $tag, $this) = @_;
   my (%types);

   &dprint("find_tag_types: looking in tags file for $tag");
   open(TAGSFILE, $file);
   seek TAGSFILE, 0, 2; # find EOF position
   my $max = tell(TAGSFILE);

   if (defined $this) {
      &dprint("find_tag_types: only looking at definitions found in class(es) $this!");
      $this =~ s/ /|/g;
      $this = "($this)";
   }
   elsif ($gbl{DBG}) {
      print "find_tag_types: local class not found, seaching for all matches\n";
   }
   my $pos = &binary_search(0, $max, $tag, \&read_routine, TAGSFILE);
   seek TAGSFILE, $pos, 0;

   LABEL: while (<TAGSFILE>) {
      if (/^($tag)\b/) {
         if (/c$/) {
            &dprint("find_tag_types: skipping class definition...");
         }
         elsif (/\/\^(.*)\b$tag\b.*\$/) {
            my $def = $1;
            if (!defined $this || /class:$this/) {
               &dprint("find_tag_types: calling find_definition($def)");
               $def = &find_definition($def);
               if (defined $def)
               {
                  &dprint("find_tag_types: found def >$def<");
                  $types{$def} = 1;
               }
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
   my @supers;

   if ($delim =~ /::/)
   {
      @supers = &find_super_classes($file, $tag);
      $tag = "$tag @supers" unless ($#supers == -1);
      &dprint("get_tag_types: static var, returning: $tag");
      return $tag;
   }

   unless ($tag eq "this" || $tag eq "super") {
      # first look for a local definition of this tag
      my $type = &find_local_type();
      if (defined $type)
      {
         @supers = &find_super_classes($file, $type);
         $type = "$type @supers" unless ($#supers == -1);
         &dprint("get_tag_types: found local type, returning $type");
         return $type;
      }
   }
   &dprint("get_tag_types: looking for 'this' class...");
   my $this = &find_this_class();
   if (defined $this) {
      @supers = &find_super_classes($file, $this);
      $this = "$this @supers" unless ($#supers == -1);
   }

   return $this if ($tag eq "this");
   if ($tag eq "super") {
      my @t = split(/ /, $this);
      shift @t;
      $this = "@t";
      return $this;
   }

   &dprint("get_tag_types: looking for $tag in tags file...");
   my @types = &find_tag_types($file, $tag, $this);
   foreach my $t (@types) {
      @supers = &find_super_classes($file, $t);
      $t = "$t @supers" unless ($#supers == -1);
   }
   &dprint("get_tag_types: returning @types");
   return @types;
}

sub _extract_member() {
   my($file, $line, $pat, $classes) = @_;
   my ($done) = 1;
   my ($val) = undef;

   if ($line =~ /^($pat\w*)/) {
      $done = 0;
      my $fullpat = $1;
      if ($line =~ /:$classes/)
      {
         # find a complete function
         if ($line =~ /($fullpat\s*\(.*?\))/) {
            $val = $1;
         }
         # find a partial function
         elsif ($line =~ /($fullpat\s*\(.*)\$/) {
            my $m = &find_rest_of_prototype($file, $line);
            $val = "$1$m";
         }
         # find a variable
         else {
            $val = $fullpat;
         }
      }
   }

   wantarray ? ($done, $val) : $val;
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
         my $val = &_extract_member($file, $_, '\w+', $classes);
         $members{$val} = 1 if (defined $val);
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
         my ($done, $val) = &_extract_member($file, $_, $pat, $classes);
         if ($done) {
            last LABEL;
         }
         elsif (defined $val) {
            $members{$val} = 1;
         }
      }
   }
   close TAGSFILE;
   my @members = keys %members;
   return sort @members;
}

sub find_rest_of_prototype() {
   my ($tagfile, $line) = @_;

   my ($file) = $line =~ /\w+\s+(\S+)/;

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
   my $g = shift;
   my $col;
   ($g->{LNUM}, $col) = $curwin->Cursor();
   my $line = $curbuf->Get($g->{LNUM});
   $g->{AFTER} = substr($line, $col+1);
   $line = substr($line, 0, $col+1);

   $g->{BEFORE} = $line;

   $line =~ s/^\s+//;
   $line =~ s/\s+$//;
   $line =~ s/\s+\(/(/;

   my @tags = split(/([\. \(]|->|::)/, $line);
   if ($g->{DBG}) {
      foreach (@tags) {
         print "study_line: split: $_\n";
      }
   }

   $g->{DELIM} = undef;
   if ($line =~ /(\.|->|::)$/)
   {
      # looking for all members of this tag
      $g->{PAT} = "";
      $g->{DELIM} = pop @tags; # pop delim
      $g->{TAG} = pop @tags;
   }
   elsif ($line =~ /(\.|->|::)/)
   {
      # looking for only members that start with the pattern after the . or ->
      $g->{PAT} = quotemeta(pop @tags);
      if ($g->{PAT} =~ /\(/) {
         # the full function name is provided, just provide options for the
         # parameter list
         $g->{PAT} = pop @tags;
         $g->{PAT} = "$g->{PAT}(";
         $g->{DELIM} = pop @tags;
         $g->{DELIM} = "$g->{DELIM}\(";
         $g->{TAG} = pop @tags;
         $g->{BEFORE} =~ s/(\.|->|::).*$/$1/;
      }
      else {
         $g->{BEFORE} =~ s/(\.|->|::)$g->{PAT}\s*$/$1/;
         $g->{DELIM} = pop @tags;
         $g->{TAG} = pop @tags;
      }
   }

   &dprint("study_line: lnum:$g->{LNUM},before:$g->{BEFORE},after:$g->{AFTER},tag:$g->{TAG},pat:$g->{PAT},delim:$g->{DELIM}.");
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

   ($line) = $line =~ /(\S+)/;

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

   unless (defined $gbl{IN_COMPLETE_MODE}) {
      $gbl{IN_COMPLETE_MODE} = $start;
      return $gbl{IN_COMPLETE_MODE};
   }
   if ($gbl{IN_COMPLETE_MODE} == 0) {
      return $gbl{IN_COMPLETE_MODE};
   }

   my ($l, $c) = $curwin->Cursor();
   if ($l == $gbl{LNUM} && $c == $gbl{COL}) {
      $gbl{IN_COMPLETE_MODE} = 1;
   }
   elsif ($gbl{COL} == -1) {
      $gbl{IN_COMPLETE_MODE} = 0;
   }
   else {
      $gbl{IN_COMPLETE_MODE} = 0;
   }
   return $gbl{IN_COMPLETE_MODE};
}

sub do_next_entry() {
   my $direction = shift;
   if ($direction =~ /F/) {
      $gbl{MEMBER_INDEX} = 0;
      $gbl{IN_COMPLETE_MODE} = 1;
   }
   elsif ($direction =~ /N/) {
      if (&in_complete_mode(0)) {
         $gbl{MEMBER_INDEX}++;
         $gbl{MEMBER_INDEX} = 0 if ($gbl{MEMBER_INDEX} > $#{$gbl{MEMBERS}});
      }
      else {
         &leave_in_insert_mode();
         return;
      }
   }
   elsif ($direction =~ /P/) {
      if (&in_complete_mode(0)) {
         $gbl{MEMBER_INDEX}--;
         $gbl{MEMBER_INDEX} = $#{$gbl{MEMBERS}} if ($gbl{MEMBER_INDEX} < 0);
      }
      else {
         &leave_in_insert_mode();
         return;
      }
   }

   my $newline = "$gbl{BEFORE}${$gbl{MEMBERS}}[$gbl{MEMBER_INDEX}]";
   $gbl{COL} = (length $newline) - 1;
   $newline .= $gbl{AFTER};

   $curbuf->Set($gbl{LNUM}, $newline);
   $curwin->Cursor($gbl{LNUM},$gbl{COL});
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
   $gbl{TYPEINDEX}++;
   $gbl{TYPEINDEX} = 0 if ($gbl{TYPEINDEX} > $#{$gbl{TYPES}});

   @{$gbl{MEMBERS}} = &get_members_of_class($gbl{TAGSFILE}, ${$gbl{TYPES}}[$gbl{TYPEINDEX}], $gbl{PAT});
   my $found = $#{$gbl{TYPES}} + 1;
   my $index = $gbl{TYPEINDEX} + 1;
   if ($#{$gbl{MEMBERS}} == -1)
   {
      VIM::Msg("No members for type: ${$gbl{TYPES}}[$gbl{TYPEINDEX}]. ($index of $found definitions)");
      &leave_in_insert_mode();
      return;
   }
   my $t = ${$gbl{TYPES}}[$gbl{TYPEINDEX}];
   $t =~ s/ /<-/g;
   VIM::Msg("members for type: $t. ($index of $found definitions)");

   push @{$gbl{MEMBERS}}, $gbl{PAT};
   &do_next_entry("F");
}

sub find_this_class() {
   VIM::DoCommand("let g:context_complete_motion_command = 'normal [['");
   my $val = VIM::Eval("InvisibleMotion(0)");

   my ($linenum, $col, $passed) = $val =~ /(\d+),(\d+)/;
   # print "find_this_class: line $linenum, col $col\n";
   unless ($linenum == 1) {
      my $continue = 1;
      FIND: while (1) {
         my $line = $curbuf->Get($linenum);
         &dprint("find_this_class: looking at line $line");
         if ($line =~ /\(/) {
            if ($line =~ /(\w+)::/) {
               # found class type
               &dprint("find_this_class: found 'this' class: $1");
               return $1;
            }
            else {
               return undef;
            }
         }
         elsif ($line =~ /^\s*$/) {
            # line is blank, failed
            &dprint("find_this_class: blank line found, break");
            last FIND;
         }
         elsif ($line =~ /}/) {
            # found the beginning of the previous function, failed
            &dprint("find_this_class: previous func found, break");
            last FIND;
         }
         elsif ($linenum == 1) {
            &dprint("find_this_class: found top of file, aborting");
            return undef;
         }
      }
      continue {
         $linenum = $linenum - 1;
      }
   }

   &dprint("find_this_class: did not find func def, searching backwards for 'class'");
   VIM::DoCommand('let g:context_complete_motion_command = "search(\'^class\\\>\', \"bW\")"');
   my $val = VIM::Eval("InvisibleMotion(1)");
   ($linenum, $col, $passed) = $val =~ /(\d+),(\d+):(\d)/;
   if ($passed) {
      my $line = $curbuf->Get($linenum);
      my($class) = $line =~ /class\s+(\w+)/;
      &dprint("find_this_class: search passed, found class: $class");
      return $class
   }

   return undef;
}

sub context_complete() {
   $gbl{COL} = -1 unless (defined $gbl{COL});
   if (&in_complete_mode(0)) {
      &dprint("context_complete: already in complete mode...");
      &do_next_entry("N");
      return;
   }

   &study_line(\%gbl);

   unless (defined $gbl{DELIM})
   {
      &leave_in_insert_mode();
      return;
   }

   $gbl{TAGSFILE} = &get_tags_file;
   if (length $gbl{TAGSFILE} == 0) {
      VIM::Msg("No tags file found!");
      &leave_in_insert_mode();
      return;
   }

   @{$gbl{TYPES}} = &get_tag_types($gbl{TAGSFILE}, $gbl{TAG}, $gbl{DELIM});
   if ($#{$gbl{TYPES}} == -1) {
      VIM::Msg("No definition found for variable $gbl{TAG}!");
      &leave_in_insert_mode();
      return;
   }
   &dprint("context_complete: found these types: @{$gbl{TYPES}}");

   $gbl{TYPEINDEX} = -1;
   &use_next_tag();
}
.

" vim: fdm=indent:sw=3:ts=3:foldignore=

