#!/usr/bin/perl -T -w

use CGI::Carp qw(fatalsToBrowser carpout);
use Time::Local;
use File::Basename;
use FileHandle;
use POSIX;
use RRDs;

BEGIN {
	carpout(\*STDOUT);
};

use strict;

use vars qw($VERSION);
my $rcs = ' $Id: rrdview.cgi,v 1.1.1.1 2002/02/26 10:21:20 oetiker Exp $ ' ;
$rcs =~ m/,v (\d+\.\d+)/;
$VERSION = ($1) ? $1 : "UNKNOWN";

my $mod_perl = (exists $ENV{MOD_PERL}) ? 1 : 0;
my $self  = basename($0);
my $imgErr; # global is good in that huge case.

doit();

sub doit {
	
	my $debug = 0;
	my $cgi   = myCGI->new();
	my $q     = $cgi->r();
	my $now   = time();
	
	my $strftime = '%A %d %B %Y %H:%M:%S %Z';
	
	my ($minD,$hourD,$mdayD,$monD,$yearD) = (myLocaltime($now));
	$cgi->paramDefault(
			   'minE'  => $minD,
			   'hourE' => $hourD,
			   'mdayE' => $mdayD,
			   'monE'  => $monD,
			   'yearE' => $yearD,
			  );
	
	($minD,$hourD,$mdayD,$monD,$yearD) = (myLocaltime($now - 86400));
	
	$cgi->paramDefault(
			   'minS'  => $minD,
			   'hourS' => $hourD,
			   'mdayS' => $mdayD,
			   'monS'  => $monD,
			   'yearS' => $yearD,
			  );
	
	
	my ($minS,$hourS,$mdayS,$monS,$yearS) = 
	  (
	   $q->param(-Name => 'minS'),
	   $q->param('hourS'),
	   $q->param('mdayS'),
	   $q->param('monS'),
	   $q->param('yearS'),
	  );
	
	my ($minE,$hourE,$mdayE,$monE,$yearE) = 
	  (
	   $q->param('minE'),
	   $q->param('hourE'),
	   $q->param('mdayE'),
	   $q->param('monE'),
	   $q->param('yearE'),
	  );
	
	my $start = myTimelocal($minS,$hourS,$mdayS,$monS,$yearS);
	my $end   = myTimelocal($minE,$hourE,$mdayE,$monE,$yearE);
	
	my $startString = strftime($strftime, localtime($start));
	my $endString   = strftime($strftime, localtime($end));
	
	$q->param('start', $start);
	$q->param('end', $end);
	
	$cgi->paramDefault(
			   'hight'   => 150,
			   'width'   => 600,
			   'rrdfile' => 'foo.rrd',
			  );
	
	my $width = $q->param(-Name=>'width');
	my $hight = $q->param(-Name=>'hight');
	my $owner = $q->param(-Name=>'owner') || "No Owner";
	my $title = $q->param(-Name=>'title') || "No Title";
	
	my $rrdfile = $q->param("rrdfile");
	
	$debug and $cgi->saveparam("/tmp/rrdmon.out");
	my $error = "";
	my $rrdinfo;
	my @dsname;
	unless (-f $rrdfile) {
		$error = "<big>File '$rrdfile' does not exist!</big><BR>\n";
	}else{
		$rrdinfo = RRDs::info $rrdfile;
		if (my $ERR=RRDs::error) {
			$error = "<big>" . $ERR . "</big><BR>\n";
			@dsname = ('RRD ERROR');
		}else{
			foreach my $key (keys %$rrdinfo) {
				if ($key =~ m/ds\[(\w+)\]\.value/) {
					push(@dsname, $1);
				}
			}
		}
	};
	
	my $dsname  = $q->param("dsname") || $dsname[0] || "unknown";
	
	if (defined $q->param(-Name=>'child')) {
		# cgi child
		imagepage($q, 
			  $cgi, 
			  $debug, 
			  $rrdfile, 
			  $dsname,
			  $owner,
			  $hight,
			  $width,
			  $start,
			  $end,
			  $title,
			 );
	}else{
		# cgi parent
		mainpage($q, 
			 $cgi, 
			 $debug, 
		 $dsname, 
		 \@dsname, 
		 $hight, 
		 $width, 
		 $error,
		 $startString,
		 $endString,
		);
	}
}

sub mainpage {
	
	my $q = shift;
	my $cgi = shift;
	my $debug = shift;
	my $dsname = shift;
	my $ldsname = shift;
	my $hight = shift;
	my $width =  shift;
	my $error = shift;
	my $startString = shift;
	my $endString = shift;

	my $queryChild = "child=yes&".$q->query_string();
	my $cgiChild = myCGI->new($queryChild);
	# CGI fork ! 
	print 
	  $q->header(),
	  #$q->start_html($q->param('owner'). " " . $q->param('title') ),
	  $q->start_html(
			 -Title=>"RRDVIEW $VERSION",
			 -Author=>'lamiral@mail.dotcom.fr',
			 -Meta=>{'keywords'=>'monitoring rrdtool rrdmon rrdview',
				 'copyright'=>'Copyleft GPL'},
			 -BGCOLOR=>'lightblue',
			),
	    ($debug) ?                   "<tt>\n" : "",
	    ($debug and $mod_perl) ?     "mod_perl PID $$<BR>\n" : "",
	    ($debug and not $mod_perl) ? "PID=$$<BR>\n" : "",
	    ($debug) ?                   "$cgi<BR>\n" : "",
	    ($debug) ?                   "$q<BR>\n" : "",
	    ($debug) ?                   "img=".\$imgErr."<BR>\n" : "",
	    ($debug) ?                   "</tt>\n" : "",
	    $q->startform(-Method=>'GET',
			  #-Enctype=>'multipart/form-data',
			 ),
	    $q->textfield(-Name=>'rrdfile', 
			-Default=>'Give me a file like foo.rrd',
			-Size=>76),
	  $q->br(),"\n",
	  $q->popup_menu(-Name=>'dsname',
			 -Values=>[@$ldsname],
			 -Default=>$dsname,
		    ),
	  $q->textfield(-Name=>'hight', -Size=>length($hight)), "x",
	  $q->textfield(-Name=>'width', -Size=>length($width)), " ",
	  $q->br(),"\n",
	  $q->image_button(-Name=>'Beautiful Image!',
			   -Src=>"$self?$queryChild",
			  ),
	  $q->br(),"\n",
	  $error,
	  $q->tt(" From "),
	  $q->textfield(-Name=>'yearS', -Size=>4),
	  $q->textfield(-Name=>'monS',  -Size=>2),
	  $q->textfield(-Name=>'mdayS', -Size=>2),
	  " ",
	  $q->textfield(-Name=>'hourS', -Size=>2),
	  $q->textfield(-Name=>'minS',  -Size=>2),
	  " $startString",
	  $q->br(),"\n",
	  $q->tt(" To", "&nbsp;" x 2),
	  $q->textfield(-Name=>'yearE', -Size=>4),
	  $q->textfield(-Name=>'monE',  -Size=>2),
	  $q->textfield(-Name=>'mdayE', -Size=>2),
	  " ",
	  $q->textfield(-Name=>'hourE', -Size=>2),
	  $q->textfield(-Name=>'minE',  -Size=>2),
	  " $endString",
	  $q->br(),"\n",
	  $cgi->paramHidden(
			    'title',
			    'owner',
			   ),
  	    $q->endform(),
	    ($debug) ? $q->dump(): "",
	    $q->end_html(),
	    "\n",
	    ;
}


sub imagepage {

	my $q = shift;
	my $cgi = shift;
	my $debug = shift;
	my $rrdfile = shift;
	my $dsname = shift;
	my $owner  = shift;
	my $hight = shift;
	my $width = shift;
	my $start = shift;
	my $end = shift;
	my $title = shift;
	    
	$debug and $cgi->saveparam("/tmp/png.out");
	
	my $output;
	RRDs::last($rrdfile);
	
	print $q->header(
			 -Type=>'image/png',
			 -Expires=>'now'
			);
	
	if($mod_perl) {
                #carp("we're running under mod_perl");
		$output = "/tmp/rrdmon.img.$$.png";
		
	}
	else {
                #we're NOT running under mod_perl
		$output = "-";
		
	}

	RRDs::graph($output,"--title", "$owner",
		    "--imgformat", "PNG",
		    "--height","$hight", "--width","$width",
		    "--start",$start,"--end",$end,
		    "DEF:value=$rrdfile:$dsname:AVERAGE",
		    "AREA:value#00FF00:$title",
		   );
	
	
	if (my $ERROR = RRDs::error()) {
		carp "ERROR: $ERROR\n";
		my $rimgErr = loadImageErrorFromVar();
		print $$rimgErr;
		return();
	}
	if($mod_perl) {
		my $fh = FileHandle->new($output, "r");
		unless (defined($fh)){
			carp("Could not open ",$output,"$!");
			return undef;
		}
		local $/ = undef;
		my $file = <$fh>;
		$fh->close();
		print $file;
	}
}


sub myLocaltime {
	my $time = shift;

	my ($min,$hour,$mday,$mon,$year) 
	  = (localtime($time))[1,2,3,4,5];

	$min  = sprintf("%02s", $min);
	$hour = sprintf("%02s", $hour);
	$mday = sprintf("% 2s", $mday);
	$mon  = sprintf("% 2s", $mon + 1);
	
	return($min,$hour,$mday,$mon,$year + 1900);	
}

sub myTimelocal {
	my ($min,$hours,$mday,$mon,$year) = @_;
	
	my $time = timelocal(0,$min,$hours,$mday,
			     $mon - 1,$year - 1900);
	return($time);
}

sub loadImageErrorFromVar {
	unless (defined ($main::imgErr)){
		$main::imgErr = pack "h*", '9805e474d0a0a1a0000000d09484442500000069000000b480000000100cdc1195000000407614d4140010680a138e69f5000080769444144587adde959607357d51e37fdb7291b42b469cb0e51f283c26028d4ce2484034020129430947b0d24c01a30482e4a30c47b480cc00d2d47adcc47843186a094999423818201a10a9408c0d670360a50c18016316b3605cb8c6958d2b4a7fee7df1290b63bcb45818c8fef1947ed5d9bfd937fbb769bf818246801c204819525793f2746a31d92001110e2070a618aa8300032040c2f590000dbc54000d600b06c22b44ca728f88a7c3f2cbc6168a019d9d08910000ee9f02cbf08a1a381ba164f880211ead6a43a63aad41bb5f6df73074502c8d6db0b3a7866400af76c7844999afc9968ea68ecb6810a74481e1b65022af90888e8debf8e2e7abb57fd7a64d8e88e93776d2bd110b830bdb3ae4602edbb24c18fa08ad9e3d662024c322b4d5852152784fa4b901595259e1dca25483ac40f8f7addbb10fb9473d4aaaea475e5d31119444515711654de759be1c5bebe321380e54f3a2f37e92222eb7c37e9d73870de8f320005cad67eadf871f15c8c1a781dadabd237da20006ba4f1bc2b1006ad520e68e08fcea34f8a979b2db63a76690444467b219e378821ebd44ab61a262ad95c12eb7651752e972232aae9a44f0c68c91b46addeb7eaf2a8ede6f49e776e4f6665f0fc7443f015f78e25e70742a6ab4c7261bc7be7873ec0c96dbe7efaa56d4a6f659d4cfada9cefcb74b72cc8d971b5c5c93a7d3a95f72e6d771888826757decebfc0a26caf0ef69014efa9ff5f1379bd527f1c16c246f1d052faee9d3b7e428888b39fa3d5a728dfade7e8fbd4d50662227f9b7bf02cb9fe9c6b566e4c5aa404150418981736182e53af64c7ed25e008fadce2823ec93c1543af88be7a3ad904d8eccf24cfaf6d00fa6ba9a2f6d77faea2fc179f423753d100007524117008d191e404e2a5304d4c9ef3806fdbdcf47979f5d46d9a981768905ea015be025111115bbdf12644443ba068759bff5f5e3a44cbde7e3724c1617941c632750008f1b73414b7397445f9f57ed5f4eacd959a00082199f1ff7e9d65ce1f7b7ec6f73436ecd63d530efae75d5052a7abefbfc8b3a6abc8f9993a6ab2d4f712a6ab4596e7ab42f5ce8a73f7179e1850db55d24a45709eab2f2f5233f8d4e4397e7fa185a852847d7cbff75352f2e4d205fe31462d930b00d5f80a433af8e03d403fb235b76bfc465a0acbda91b70bfeccf02c5c62d177abddeee358f1fb224c34282c353c78d0bcf39e59957fe15758628fe442c34b990f3e75ebae79622968311193555b3dadcebef5cd5397073dacb13b7988486c39797ea988804c88f9eda7648f3d86f385c2827da5d07adb9f2dd397bf8f7cc653dcec292e6d786479d37e40f7b5d989df8ab00cb7fe1eaec1dd4953b1c2d99f57dd38a405d31d69c74cbfb9f2fc5df53000bc0e71d87d0c18ddab23b99d8f1208973fe47ac4c31189cb7dd44e14abc934678f4055aafe97e9eb41b56c108c3ee76c1cf9f728303febb9b3fb3282febf3e2f8fe9987bc3892cb8c3e18247e246444cda36811b2da0b111d923cb11311a8931c7e4377db5c14444a0cb5bcad8560111949d74412238ca019257faae24a0a04037287bdb93a686e5ed29a322e4ed5afa88134444c6deec55de6f57363e98a95d3d34802afcf0ed74741c4df375d5ef06c76991d0aa30e1be7a81db7b607825253533fb000b97e5861ade67228be24583004bd68a60fa39d32a7565af6e4dfebd7d0d954a5f5aef2edbe89bd5fc71a72aaa52a793d4e7af464fa6396983170aec910d57fe5d1d779a98300bee0d09ee4e2e8b975097a3677b97b8f995c33e7fdc77dd62a836663e0c97e77d17b4b7f72c5fbceee117b04a822bce4ea3dcde78c26656e9cb0de131906926f6d63b89babea1cad4dae454693ff5f70557bb16133429273adc8110657cbfbaa15538c46a4fcc173831d46885ead4de7835aad1c0b8d2d957d0b45959ce85a569426f5e696bfe34d625bdbd1cab6acb83a729bf87db424fb2a22620361eab1fe4a572ccccafcf8a3afb30a21744e8b5251c407c7a5bdfc505036c2c2b6cf86d90f0fef35b5a054260292d2f3e28663758488efe030c800619065c4e7ae99dc1f2011194326571aff934e53bbe3aa681a86151aa41798a264407438d44db14b267ed8c9ca8a4516073fe0b53b38b06c4b8903f091182c17bcf6176953ef259cb697c880c898ed9b86aa4efd26bd635341f2b147aa1d22bcf7f5dad2d9394d2b7fda3fc81f4bf5f391b4448693478cc536552f69dc2db71b8da52ed0201c175f0f1c37dc42231febfdd8fe54814f7f986784c43ad5a0c8decfaef6fcec25dee4dd8f4be8188816a77cf175d1f54b77b5acb6f4a6c6c60f022243deadc7e4c2c9f9779edd79a275e0164444695bbdf9d5d94f9ff5f085435cfb82ec0d03625c801692fc882cc62affba5ee8772d78de3938abc57eea11a5de0f2fecb4809ffd52ad1168bf7fafaba6e6ef1b1a07b6d9c08be0c833eb2e97d9153375b37f8e2f494a7eff1d0274ae1ab57db172e9803fe6ccfd406a159bd1a4070cb1f3aa3499df8576ed21b0eb3aeb86c55335debe36ff3785756f3a431984539616c69f11797e48905db4ff2505eb96642a81992f00ab9a028136168f713219a2b26df50a30d8c90aae43626c573d36c866a61cd834d2e95e493b7d71d699caee630480dd50802254143e9abe75aaf6a49034746e42a7e8e8bbd1a238fb9ceeabe012da3b6a496ce3efeef1a1b437442a6f3171539fa52222278bcdf4db09add60419bd4614ce60657c9fa77ea05bec49117eaf277a597afc9939b211113a0438a9bacdaec0f3734acab9ef6e6cda52f0b1bef39a814b2e78a1222218129e9dcdee3cc9ea47c4ec80619bf4443f9374a72be4d20328ba5e8db3519bfa71b44ea345e9bb023cfefa7179c1d16f65940c9b27e58f0f31b82252fca9d9b2973eac53d765ccd696f55eb94171ec1c27d6d46e019248bbc1d50f4eb14d55fd9c68c8f75708e1fc01ee1a6f570ea646006d00ca10857fa1caff107d7f7057eba98065000000009454e444ea240628';
	}
	return(\$main::imgErr);
}


package myCGI;

use CGI;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};
	$self->{'CGI'} = CGI->new(shift);
	bless ($self, $class);
	return $self;
}

sub r {
	my $self = shift;
	return($self->{'CGI'});
}

sub DESTROY {
	my $self = shift;

}

sub paramDefault {
	my $self    = shift;
	my %param   = @_;
	
	foreach my $param (keys(%param)) {
		unless (defined($self->r->param(-Name=>$param))) {
			$self->r->param(-Name=>$param, -Value=>$param{$param});
		}
	}
	return values(%param);
}

sub paramHidden {
	my $self    = shift;
	my @hidden = @_;

	my @result;
	foreach my $param (@hidden) {
		push(@result, $self->r->hidden(-Name=>$param));
	}
	return(@result);
}

sub saveparam {
	my $self = shift;
	my $savefile = shift;
	my $fh = FileHandle->new($savefile, "w");
	defined($fh) || confess("Error opening $savefile (w): $!");
	$self->r->save($fh);
	$fh->close();
	chmod 0777, $savefile;
}


=head1 NAME

rrdview.cgi - Perl CGI software to graph rrd image online

=head1 SYNOPSIS

Put it on any cgi-bin/ directory, use a browser, click and fill in an
rrd file in the first textfield (replacing foo.rrd). The file belongs
to the web server. 

=head1 DESCRIPTION

Just another rrd viewer. 

=head1 TODO

 . An upload textfield to allow graphing client rrd files.
 . Deal with LAST, MAX, MIN RRA.

=head1 AUTHOR

Gilles LAMIRAL 
lamiral@mail.dotcom.fr

=head1 SEE ALSO

rrdtool(1), perl(1).

=cut



