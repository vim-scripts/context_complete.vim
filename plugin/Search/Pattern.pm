package Search::Pattern;
# use strict;
$Search::Pattern::VERSION = 1.00;

sub new {
   my $self = {};
   shift; # get rid of "Search::Pattern"

   $self->{SEARCH_PAT} = shift;
   $self->{DEFAULT_SEARCH_PAT} = '/%t %c::%f/^}, /class %c(\s*:\s*(public|private|protected) %s)?/';
   $self->{IGNORE_KEYWORDS} = shift;
   $self->{DEFAULT_IGNORE_KEYWORDS} = "public private protected class return";

   bless($self);
   return $self;
}

sub _create_search_pattern {
   my ($full, $special) = @_;

   $full =~ s/(?<!\\)\(/(\?:/g;
   $full =~ s/\s+/\\s+/g;
   my ($pat, $stop) = $full =~ /\/(.*)\/(.*)?$/;

   my $vars;
   if ($special) {
      # we only care about one...
      unless ($pat =~ /$special/) {
         return undef;
      }
      $vars = '($special)';
      $pat =~ s/$special/(\\w+)/;
      $pat =~ s/(%[cfts])/\\w+/g;
   }
   else {
      my (@matches) = $pat =~ /(%[cfts])/g;
      $vars = "(@matches)";

      $vars =~ s/%t/\$type/;
      $vars =~ s/%c/\$class/;
      $vars =~ s/%f/\$func/;
      $vars =~ s/%s/\$super/;
      $vars =~ s/ /,/g;

      $pat =~ s/%\w/(\\w+)/g;
   }
   return ($vars, $pat, $stop);
}

sub _get_search_pat {
   my ($contains, $pat) = @_;
   my (@patts) = split(/,/,$pat);
   # my (@rets) = grep(/$contains/, @patts);

   # return @rets;
   return grep(/$contains/, @patts);
}

sub _create_ignore_pattern {
   my $pat = shift;
   $pat =~ s/^\s*(.+)\s*$/$1/;
   $pat =~ s/\s+/|/g;
   return "($pat)";
}

sub ignore_keywords {
   my $self = shift;

   unless (defined $self->{IGNORE}) {
      if (defined $self->{IGNORE_KEYWORDS}) {
         $self->{IGNORE} = &_create_ignore_pattern($self->{IGNORE_KEYWORDS});
      }
      else {
         $self->{IGNORE} = &_create_ignore_pattern($self->{DEFAULT_IGNORE_KEYWORDS});
      }
   }
   return $self->{IGNORE};
}

sub get_item {
   my ($self, $line, $item) = @_;

   unless (defined @{$self->{$item}}) {
      my (@pats) = &_get_search_pat($item, $self->{SEARCH_PAT});
      unless (@pats) {
         # use defaults instead
         @pats = &_get_search_pat($item, $self->{DEFAULT_SEARCH_PAT});
      }
      foreach my $p (@pats) {
         my (@ret) = &_create_search_pattern($p, $item);
         push @{$self->{$item}}, @ret;
      }
   }

   my ($stop, $val, $special);
   $stop = 0;
   my @all = @{$self->{$item}};
   while (@all) {
      my $v = shift @all;
      my $p = shift @all;
      my $s = shift @all;
      if ($s and $line =~ /$s/) {
         $stop = 1;
         last;
      }
      eval "$v = \$line =~ /$p/";
      if ($special) {
         $val = $special;
         last;
      }
   }

   wantarray ? ($stop, $val) : $val;
}

1;

# vim: sw=3:fdi=:fdm=indent
