package MD5;  # legacy stuff

use strict;
use vars qw($VERSION @ISA);

$VERSION = '2.01';  # $Date: 1999/08/05 23:17:54 $

require Digest::MD5;
@ISA=qw(Digest::MD5);

sub hash    { shift->new->add(@_)->digest;    }
sub hexhash { shift->new->add(@_)->hexdigest; }

1;
__END__

=head1 NAME

MD5 - Perl interface to the MD5 Message-Digest Algorithm

=head1 SYNOPSIS

 use MD5;

 $context = new MD5;
 $context->reset();
    
 $context->add(LIST);
 $context->addfile(HANDLE);
    
 $digest = $context->digest();
 $string = $context->hexdigest();

 $digest = MD5->hash(SCALAR);
 $string = MD5->hexhash(SCALAR);

=head1 DESCRIPTION

The C<MD5> module is B<depreciated>.  Use C<Digest::MD5> instead.

The current C<MD5> module is just a wrapper around the C<Digest::MD5>
module.  It is provided so that legacy code that rely on the old
interface still work and get the speed benefit of the new module.

In addition to the methods provided for C<Digest::MD5> objects, this
module provide the class methods MD5->hash() and MD5->hexhash() that
basically do the same as the md5() and md5_hex() functions provided by
C<Digest::MD5>.

=head1 SEE ALSO

L<Digest::MD5>

=cut
