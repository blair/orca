use ExtUtils::MakeMaker;
use File::Copy qw();
my $arg = $ARGV[0] || "";
my($DOXS, $DONOXS);
$DONOXS = shift if	$arg =~ /^noxs/i	and
			-f "MANIFEST.NOXSUB"	and
			-f "Dumper.pm.NOXSUB";
$DOXS 	= shift if	$arg =~ /^xs/i		and
			-f "MANIFEST.XSUB"	and
			-f "Dumper.xs.XSUB"	and
			-f "Dumper.pm.XSUB";

if ($DONOXS) {
    print STDERR "Disabling XS in sources...\n";
    die "***** Failed, sources could be inconsistent! *****\n" unless
    File::Copy::move('MANIFEST',	'MANIFEST.XSUB')	and
    File::Copy::move('MANIFEST.NOXSUB',	'MANIFEST')		and
    File::Copy::move('Dumper.pm',	'Dumper.pm.XSUB')	and
    File::Copy::move('Dumper.xs',	'Dumper.xs.XSUB')	and
    File::Copy::move('Dumper.pm.NOXSUB','Dumper.pm');
}
elsif ($DOXS) {
    print STDERR "Enabling XS in sources...\n";
    die "***** Failed, sources could be inconsistent! *****\n" unless
    File::Copy::move('MANIFEST',	'MANIFEST.NOXSUB')	and
    File::Copy::move('MANIFEST.XSUB',	'MANIFEST')		and
    File::Copy::move('Dumper.pm',	'Dumper.pm.NOXSUB')	and
    File::Copy::move('Dumper.xs.XSUB',	'Dumper.xs')		and
    File::Copy::move('Dumper.pm.XSUB',	'Dumper.pm');
}

WriteMakefile(
	NAME		=> "Data::Dumper",
	VERSION_FROM	=> 'Dumper.pm',
	DISTNAME	=> 'Data-Dumper',
	(
	 $] > 5.00470 ?
	 (INSTALLDIRS	=> 'perl') :
	 ()
	),
	'dist'		=> {
			     COMPRESS	=> 'gzip -9f',
	      		     SUFFIX	=> 'gz',
			   },
);
