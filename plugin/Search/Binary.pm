#
# $Id: Binary.pm,v 1.3 2005/02/25 18:26:44 deggum Exp $
#
# Seach::Binary

package Search::Binary;

=head1 NAME

Search::Binary -- generic binary search

=head1 SYNOPSIS

  use Seach::Binary;
  $pos = binary_search($min, $max, $val, $read, $handle, [$size]);

=head1 DESCRIPTION

C<binary_search> implements a generic binary search algorithm returning the
I<position> of the first I<record> whose I<index value> is greater than or
equal to C<$val>. The search routine does not define any of the terms
I<position>, I<record> or I<index value>, but leaves their interpretation
and implementation to the user supplied function C<&$read()>. The only
restriction is that positions must be integer scalars.

During the search the read function will be called with three arguments:
the input parameters C<$handle> and C<$val>, and a position.  If the position
is not C<undef>, the read function should read the first whole record starting
at or after the position; otherwise, the read function should read the record
immediately following the last record it read.  The search algorithm will
guarantee that the first call to the read function will not be with a position
of C<undef>.  The read function needs to return a two element array consisting
of the result of comparing C<$val> with the index value of the read record and
the position of the read record. The comparison value must be positive if
C<$val> is strictly greater than the index value of the read record, C<0>
if equal, and negative if strictly less. Furthermore, the returned position
value must be greater than or equal to the position the read function was
called with.

The input parameters C<$min> and C<$max> are positions and represents the
extent of the search. Only records which begin at positions within this range
(inclusive) will be searched. Moreover, C<$min> must be the starting position
of a record. If present C<$size> is a difference between positions and
determines when the algorithms switches to a sequential search. C<$val> is
an index value. The value of C<$handle> is of no consequence to the binary
search algorithm; it is merely passed as a convenience to the read function.

=head1 COPYRIGHT

  Copyright 1998, Erik Rantapaa

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

# use strict;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(binary_search);

$VERSION = "0.95";

sub binary_search {
        shift; # get rid of 'Search::Binary'
	my $posmin = shift;
	my $posmax = shift;
	my $target = shift;
	my $readfn = shift;
	my $handle = shift;
	my $smallblock = shift || 512;

	my ($x, $compare, $mid, $lastmid);
	my ($seeks, $reads);

        my $filemax = $posmax;

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
	while ($posmin <= $posmax && $posmin < $filemax) {

		# same loop invarient as above applies here

		$reads++;
		($compare, $posmin) = &$readfn($handle, $target, $x);
		last unless (defined($compare) && $compare > 0);
		$x = undef;
	}
	wantarray ? ($posmin, $seeks, $reads) : $posmin;
}

1;

# vim: ts=8
