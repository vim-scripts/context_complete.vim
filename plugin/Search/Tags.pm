package Search::Tags;
# use strict;
$Search::Tags::VERSION = 1.00;
use Search::Binary;
use IO::File;

sub new {
   my $self = {};
   shift; # get rid of "Search::Tags"

   $self->{FILENAME} = shift;
   $self->{FILEHANDLE} = IO::File->new;
   &_prepare_file($self);

   bless $self;
   return $self;
}

sub _prepare_file {
   my $self = shift;
   my $mtime = shift;
   open($self->{FILEHANDLE}, $self->{FILENAME}) or die "Can't open tag file $self->{FILENAME}! $!";

   seek $self->{FILEHANDLE}, 0, 2; # find EOF position
   $self->{MAX} = tell($self->{FILEHANDLE});

   if ($mtime) {
      $self->{MTIME} = $mtime;
   }
   else {
      my (@info) = stat $self->{FILENAME};
      $self->{MTIME} = $info[9];
   }
}

sub DESTROY {
   my $self = shift;
   close $self->{FILEHANDLE};
}

sub get_tags_file {
   my ($self, $tags) = @_;
   my @files = split(/,/, $tags);
   foreach (@files) {
      return $_ if (-r $_);
   }

   return undef;
}

sub filename {
   my $self = shift;
   return $self->{FILENAME};
}

sub binary_search {
   my ($self, $tag) = @_;
  
   my $pos = Search::Binary->binary_search(0, $self->{MAX}, $tag,
      \&Search::Tags::read_routine, $self->{FILEHANDLE});

   seek $self->{FILEHANDLE}, $pos, 0;
}

sub reset {
   my $self = shift;
   seek $self->{FILEHANDLE}, 0, 0;
}

sub check_for_updates {
   my $self = shift;
   my (@info) = stat $self->{FILENAME};
   my $mtime = $info[9];
   if ($mtime > $self->{MTIME}) {
      close $self->{FILEHANDLE};
      &_prepare_file($self, $mtime);
      return 1;
   }
   return 0;
}

sub mtime {
   my $self = shift;
   return $self->{MTIME};
}

sub next_line {
   my $self = shift;
   my $handle = $self->{FILEHANDLE};
   my $line = <$handle>;
   return $line;
}
 
# only compares the $target with the first word in the tag file.
sub read_routine {
   my ($handle, $target, $pos) = @_;
   my ($compare, $newpos);

   my $line;
   if (defined $pos) {
      seek $handle, $pos, 0;
      $line = <$handle> unless ($pos == 0); # $pos will usually be in the
                                            # middle of the line
   }
   $newpos = tell($handle);
   $line = <$handle>;

   ($line) = $line =~ /(\S+)/; # only interested in the first word

   $compare = $target cmp $line;
   return ($compare, $newpos);
}

1;

# vim: sw=3:fdi=:fdm=indent
