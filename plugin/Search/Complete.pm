package Search::Complete;
# use strict;
$Search::Complete::VERSION = 1.00;

sub new {
   my $self = {};
   shift; # get rid of "Search::Complete"

   my ($lnum, $col, $line) = @_;

   $self->{AFTER} = substr($line, $col+1);
   $line = substr($line, 0, $col+1);

   my $before = $line;

   $line =~ s/^\s+//;
   $line =~ s/\s+$//;
   $line =~ s/\s+\(/(/;
   $line =~ s/\(.*?\)/()/g;

   my $punct = '[^\s\w]+';
   @{ $self->{ALLTAGS} } = split(/($punct)/, $line);
   @{ $self->{TAGCHAIN} } = @{ $self->{ALLTAGS} };

   my $delim;
   my ($pat, $tag);
   $tag = pop @{ $self->{TAGCHAIN} };
   if ($tag eq "(") {
      # the full function name is provided, just provide options
      # for the parameter list
      $pat = pop @{ $self->{TAGCHAIN} };
      $pat = "$pat(";
      $delim = pop @{ $self->{TAGCHAIN} };
      $delim = "$delim\(";
      $tag = pop @{ $self->{TAGCHAIN} };
      $before =~ s/($punct).*$/$1/;
   }
   elsif ($tag =~ /$punct/) {
      # looking for all members of this tag
      $delim = $tag;
      $tag = pop @{ $self->{TAGCHAIN} };
   }
   elsif (@{ $self->{TAGCHAIN} }) {
      # only looking for members that start with a pattern
      $pat = quotemeta($tag);
      $before =~ s/($punct)$pat\s*$/$1/;
      $delim = pop @{ $self->{TAGCHAIN} };
      $tag = pop @{ $self->{TAGCHAIN} };
   }
   else {
      # local variable completion
      $pat = quotemeta($tag);
      $tag = "this";
      $delim = ".";
      $before =~ s/(\s+).*/$1/;
   }

   $self->{PAT} = $pat;
   $self->{TAG} = $tag;
   $self->{DELIM} = $delim;
   $self->{LINE} = $line;
   $self->{BEFORE} = $before;
   $self->{IN_COMPLETE_MODE} = 0;
   $self->{LNUM} = $lnum;
   $self->{COL} = -1;
   $self->{MEMBERINDEX} = 0;
   $self->{TYPEINDEX} = undef;

   bless($self);
   return $self;
}

sub in_complete_mode {
   my ($self, $l, $c) = @_;
   return 0 unless ($self->{IN_COMPLETE_MODE});
   $self->{IN_COMPLETE_MODE} = ($l == $self->{LNUM} && $c == $self->{COL});
}

sub leave_complete_mode {
   my $self = shift;
   $self->{IN_COMPLETE_MODE} = 0;
}

sub is_method {
   my $self = shift;
   $self->{DELIM} =~ /\)/;
}

sub tag {
   my ($self) = shift;
   $self->{TAG};
}

sub types {
   my $self = shift;
   @{$self->{TYPES}} = @_ if (@_);
   @{$self->{TYPES}};
}

sub clear_members {
   my $self = shift;
   @{$self->{MEMBERS}} = ();
}

sub members {
   my $self = shift;
   if (@_) {
      @{$self->{MEMBERS}} = @_;
      unshift @{$self->{MEMBERS}}, $self->{PAT};
   }
   @{ $self->{MEMBERS} };
}

sub next_member {
   my ($self, $dir) = @_;
   $self->{MEMBERINDEX} = $self->{MEMBERINDEX} + $dir;
   $self->{MEMBERINDEX} = @{$self->{MEMBERS}}-1 if ($self->{MEMBERINDEX} < 0);
   $self->{MEMBERINDEX} = 0 if ($self->{MEMBERINDEX} >= @{$self->{MEMBERS}});
   ${$self->{MEMBERS}}[$self->{MEMBERINDEX}];
}

sub next_completion {
   my ($self, $direction, @pos) = @_;

   $self->{IN_COMPLETE_MODE} = 1;
   my $mem = &next_member($self, $direction || 1);

   my $newline = "$self->{BEFORE}$mem";
   $self->{COL} = (length $newline) - 1;
   $newline .= $self->{AFTER};
}

sub spot {
   my $self = shift;
   return ($self->{LNUM}, $self->{COL});
}

sub pat {
   my $self = shift;
   $self->{PAT} = shift if (@_);
   return $self->{PAT};
}

sub next_type {
   my $self = shift;
   if (not defined $self->{TYPEINDEX} or $self->{TYPEINDEX} >= $#{$self->{TYPES}}) {
      $self->{TYPEINDEX} = 0;
   }
   else {
      $self->{TYPEINDEX}++;
   }
   $self->{MEMBERINDEX} = 0;
   ${$self->{TYPES}}[$self->{TYPEINDEX}];
}

sub typeindex {
   my $self = shift;
   $self->{TYPEINDEX};
}

sub memberindex {
   my $self = shift;
   $self->{MEMBERINDEX};
}

1;

# vim: sw=3:fdi=:fdm=indent
