#!/usr/bin/perl -w

# Q: Who wrote this?
# Bill Nash - billn@billn.net / billn@gblx.net
#
# Q: Why?
# SNMP retrieval and storage of interface utilization, ala MRTG.
#
# Q: Is this a supported utility?
# Barely. That means if there's a serious problem with it, you can email me. I'll take feature requests
# provided they're presented in an intelligent manner. I will NOT write scripts for you. There's a plethora
# of information available to you, stop being lazy and do it yourself. Mostly, I wrote this for myself. I
# released it to the community at large because it's useful. Your mileage may vary. This code carries no 
# warranty and I'm not responsible if you do something stupid with it.
#
# Q: Why does the author sound like a grumpy curmudgeon?
# Because I'm releasing a utility to the public, and I detest people. I read the MRTG lists. I know what you 
# people are and are not capable of. I could jump up on my soapbox and rant about the general laziness of people,
# but no one will care. The user base at large is full of lazy bastards who just want someone else to create something
# that does exactly what they want, with as little effort required on their part.
#
# Q: Is it safe to ask questions about this utility?
# I will be more than happy to entertain discussions about this utility, provided:
#	It's a discussion of perl mechanics, and the person asking the question knows something about Perl.
#	It's a discussion of SNMP mechanics, and the person asking the question isn't asking where to find Mibs/objects.
#	You're a Playboy Bunny and you'd like to meet me for dinner.
#
# Q: Your code sucks, billn, why does this do [such and such], and why didn't you do condense [this and this]?
# This is intended to be a simple utility. No fancy obsfucation, no serious attention to efficiency. The only real creative 
# parts are using ifDescr/ifName as an interface basis (which offsets the nasty ifIndex shift problem by using ifIndex has a 
# value of the key, ifDescr/ifName, instead of vice versa. The ifIndex can change all it wants. Don't go saying 'Well, what if 
# interface name changes?', because I'll just say "Then it's a new interface. Cope."
# Also, by NOT obfuscating functions and keeping things simple, I'd hope people looking at this script that aren't fully versed
# in the intricacies and foibles of SNMP, PERL and RRD will have an easier time grasping the concepts, and maybe learn a bit from 
# this. Much of the code contained in here is interchangable, data sources can be substituted left and right, and I fully expect
# someone to hack this into a shining pearl of relative usefulness on a regular basis. It's not the end all, be all of SNMP pollers,
# but I expect it'll find widespread use.

$local_dir = "/usr/local/rrdtool-1.0.28";	# Where this script lives
$rrd_store = "$local_dir/rrd";		# Where to keep our rrd datastores

$debug = 0;

# This is Net::SNMP-2.00. It's not included with this script. Try CPAN.
use Net::SNMP;

# RRD Perl module. If you don't have it, why are you here?
use RRDs;

# This piece can be ripped out and subbed for any number of data storage methods. This is a simple method
# that works for those handling only a few devices. IP addresses are important because I don't use hostname
# matches for the SNMP calls. This eliminates DNS dependancies, but does require you to maintain your code or
# host registries.

$devices{"Hades"}{'ip_address'} = "10.0.0.254"; # my switch
$devices{"Hades"}{'snmp_read'} = "public";
$devices{"Bifrost"}{'ip_address'} = "10.0.0.253"; # my router
$devices{"Bifrost"}{'snmp_read'} = "public";

# Standard SNMP mib2 jazz. Feel free to edit. YMMV.

# Variables from the %oids hash we'll be referencing later. It's easier to call them by a name.
# What, you think I'm gonna memorize SNMP oids? =P

@poll_int = (
		"ifDescr",
		"ifOperStatus",
		"ifAlias",
		"ifInErrors",
		"ifInOctets",
		"ifOutErrors",
		"ifOutOctets",
		"ifSpeed"
);

%oids = (
	sysDescr              => "1.3.6.1.2.1.1.1.0",
	sysName               => "1.3.6.1.2.1.1.5.0",
	sysUptime             => "1.3.6.1.2.1.1.3.0",
	ifNumber              => "1.3.6.1.2.1.2.1.0",
	#ifDescr               => "1.3.6.1.2.1.2.2.1.2",
	ifType                => "1.3.6.1.2.1.2.2.1.3",
	ifSpeed               => "1.3.6.1.2.1.2.2.1.5",
	ifPhysAddress         => "1.3.6.1.2.1.2.2.1.6",
	ifAdminStatus         => "1.3.6.1.2.1.2.2.1.7", 
	ifOperStatus          => "1.3.6.1.2.1.2.2.1.8",
	ifAlias               => "1.3.6.1.2.1.31.1.1.1.18",
	ifInErrors            => "1.3.6.1.2.1.2.2.1.14",
	ifInOctets            => "1.3.6.1.2.1.2.2.1.10",
	ifInUnkProtos         => "1.3.6.1.2.1.2.2.1.15",
	ifLastChange          => "1.3.6.1.2.1.2.2.1.19",
	ifDescr                => "1.3.6.1.2.1.31.1.1.1.1", # was ifXName, subbed for ifDescr
	ifOutDiscards         => "1.3.6.1.2.1.2.2.1.19",
	ifOutErrors           => "1.3.6.1.2.1.2.2.1.20",
	ifOutOctets           => "1.3.6.1.2.1.2.2.1.16"
);

while(1) {
	$start = time;

	foreach $device_name (keys %devices) {
		undef(%ifAdmin);
		# Establish an snmp session with the device
        	my($session, $error) = Net::SNMP->session(
                                            Hostname  => $devices{$device_name}{'ip_address'},
                                            Community => $devices{$device_name}{'snmp_read'},
                                            Translate => 1,
                                            VerifyIP  => 1
        	);

	# This example may seem a bit long and drawn out, but it's better for a clear view of how the procedure works
	# It's entirely possible (and more efficient) to restructure this into a tight bundle of reusable code.
        	if ($session) {
                	print "$device_name: SNMP Session established ($device_name, $devices{$device_name}{'ip_address'})\n" if ($debug);

		# First step, find all the administratively active interfaces. Typically, this should be the ONLY
		# table that takes a walk across all interfaces. If you're doing smart and clean device management,
		# all unused/undesignated interfaces should be admin'd down and scrubbed of configs. If you don't
		# maintain this kind of device policy, don't cry to me because things take longer than you expect.

		# For the sake of efficiency, I should note here that this set of data doesn't HAVE to be generated with an SNMP poll
		# You can have an entirely external management system here that dictates what interfaces are tracked. You can rip this
		# chunk out and replace it with something else entirely.

		#print "Retrieving ifAdminStatus table: $oids{'ifAdminStatus'}\n" if ($debug);
                	$response = $session->get_table($oids{'ifAdminStatus'});
                	if($error_message = $session->error) {
                        	if($error_message eq "Requested table is empty" ||
                           		$error_message eq "Recieved SNMP noSuchName(2) error-status at error-index 1") {}
                        	else {
                                	print STDERR "ifAdmin table get failed ($device_name: $oids{'ifAdminStatus'}): $error_message\n"
                        	}	# end if
				next; # Can't get an ifAdminStatus table? No active interfaces or a borked SNMP engine. Next!
                	} # end if

                	%array = %{$response};
                	foreach $key (keys %array) {

				$ifIndex = $key;
				$ifIndex =~ s/^$oids{'ifAdminStatus'}.//g;

			# Hash the ifAdminStatus data if the status is 1. We aren't going to bother with any 
			# interfaces that aren't set active.
			# For the curious, possible values here are:
			# @OperStatus=("null", "Up", "Down", "Looped", "null", "Dormant", "Missing");

                       		$ifAdmin{$ifIndex} = $array{$key};
				#print "$device_name: ifIndex $ifIndex, ifAdmin $array{$key} $ifAdmin{$ifIndex}\n" if ($debug);
                	} #end foreach

			# Cycle through all The admin'd active interfaces, by ifIndex
			foreach $ifIndex (keys %ifAdmin) {
				undef(@interface_rrd);
				next if ($ifAdmin{$ifIndex} != 1);
			# Cycle through all the objects we want to track for each interface. This 
			# is a highly reusable set of code, set up to perform the same task repeatedly for 
			# (potentially long) lists of variables.
				foreach $object (@poll_int) {
				# get the numeric oid values from the oids table
					$object_id = $oids{$object};

				# go get the object.
	                		$response = $session->get_request("$object_id.$ifIndex");
      	         			if($error_message = $session->error) {
						if($error_message eq "Recieved SNMP noSuchName(2) error-status at error-index 1") {
						# It's a common occurence to poll an interface for an object that it
						# doesn't support, so we'll just U the object.
							$data{$device_name}{$ifIndex}{$object} = "U";
						} #end if

					# Whatever the object was, it didn't want to be 'gotten', so screw it.
       	                			print STDERR "Object get failed ($device_name: $object_id.$ifIndex):$error_message\n" if ($debug);
						next;
                			} #end if

                			%array = %{$response};

				# Shucks, got data, get to work. This chunk of code is pretty generic, and you'll 
				# recognize it from up above. I *could* use a single iteration here, but better save
				# in case the snmp engine did something hokey, or we used a table base variable in the get.
				# The multilayer hash prolly makes some of you twitch to see, but hey, if you don't like it,
				# why are you reading my code to begin with? It works, take a hike.
				# Anyway, it's an extensible memory structure that doesn't care what you're stuffing into it.

                			foreach $key (keys %array) {
		                        	$ifIndex = $key;
               			        	$ifIndex =~ s/^$oids{$object}.//g;

                        			$data{$device_name}{$ifIndex}{$object} = $array{$key};
						#print "$device_name: ifIndex $ifIndex, $object = $data{$device_name}{$ifIndex}{$object}\n";
                			} #end foreach
				} #end foreach
			} #end foreach

		# Alright, so at this point, we should have a full set of data (whatever we requested) for 
		# each active interface.
		# This whole next section is all about what we do with any given piece of data, so if you're doing
		# customization beyond what I've included, here's your sandbox, here's your shovel. Go build me a Buick.

		# My primary goal for this utility is low overhead interface utilization tracking for my router and switch.
		# In combination with RRDtool's graphing abilities, poof, it's a skimpy but solid (and extensible) replacement
		# for MRTG. Don't get me wrong, I like MRTG, but RRDtool a lot easier to do flexible things with. The fact
		# that this whole piece is in Perl provides a working template for bigger and crazier things, like using 
		# a real SQL db for tracking port data, or real time data feeds to Linus knows what. With these things in
		# mind, let's start tossing some data.

		#        ifSpeed               => "1.3.6.1.2.1.2.2.1.5",
		# Since we're doing traffic graphing, it's helpful to know the size of the pipe we're tracking.

        	#	ifOperStatus          => "1.3.6.1.2.1.2.2.1.8",
		# If the interface is down for some reason, it'd be good to have a way to represent that.

        	#	ifAlias               => "1.3.6.1.2.1.31.1.1.1.18",
		# ifAlias is usually a human supplied interface description. 

		#       ifInErrors            => "1.3.6.1.2.1.2.2.1.14",
		#       ifInOctets            => "1.3.6.1.2.1.2.2.1.10",
		#       ifInUnkProtos         => "1.3.6.1.2.1.2.2.1.15",
		#       ifOutDiscards         => "1.3.6.1.2.1.2.2.1.19",
		#       ifOutErrors           => "1.3.6.1.2.1.2.2.1.20",
		#       ifOutOctets           => "1.3.6.1.2.1.2.2.1.16"
		# These should be pretty obvious. No, that's not short for Uncle Protos.

		#       ifDescr               => "1.3.6.1.2.1.2.2.1.2",
		# This is usually the name for an interface. Very important variable.
		# Since I'm testing with a cisco catalyst, I've switched ifDescr for ifName/ifXName, up top. Less pain.

		# We need a place to store this stuff, so let's check out storage structures

			foreach $device_name (keys %data) {
				#print "Generating/feeding data for $device_name\n";
				foreach $ifIndex (keys %{$data{$device_name}}) {

					$ifDescr = $data{$device_name}{$ifIndex}{'ifDescr'};
					if ($ifDescr eq "") {
						#print "$device_name ifIndex $ifIndex apparantly has a null ifDescr -> [$ifDescr], skipping\n";
						next;
					} # end if

			# If you recognize where I stole these from, you may already know me as '[tHUg]Heartless'
			# I prefer the Aug and the TMP, and I fear no AWP. =)
			# This set of regexp's is for scrubbing potentially exciting characters from interface names before 
			# using them as the basis for storing files. Some OS's and file systems may object to some of these 
			# characters, so, better safe than annoyed.
			# You'll note I don't provide facilities for reverting this. I just collect the stuff. Display is your problem.

			    		$ifDescr =~ s/ /_/g;
			    		$ifDescr =~ s/\=/\[EQUAL\]/g;
			    		$ifDescr =~ s/\,/\[CMA\]/g;
			    		$ifDescr =~ s/;/\[SMICLN\]/g;
			   	 	$ifDescr =~ s/:/\[CLN\]/g;
			  	  	$ifDescr =~ s/\"/\[DBLQT\]/g;
			 	   	$ifDescr =~ s/\'/\[SNGLQT\]/g;
				    	$ifDescr =~ s/\{/\[LB2\]/g;
				    	$ifDescr =~ s/\}/\[RB2\]/g;
				    	$ifDescr =~ s/\+/\[PLS\]/g;
				    	$ifDescr =~ s/\-/\[DSH\]/g;
				    	$ifDescr =~ s/\(/\[LPRN\]/g;
				    	$ifDescr =~ s/\)/\[RPRN\]/g;
				    	$ifDescr =~ s/\*/\[STR\]/g;
				    	$ifDescr =~ s/\&/\[AND\]/g;
				    	$ifDescr =~ s/\|/\[PIPE\]/g;
				    	$ifDescr =~ s/\\/\[BSLSH\]/g;
				    	$ifDescr =~ s/\//\[FSLSH\]/g;
				    	$ifDescr =~ s/\?/\[QUESTN\]/g;
				    	$ifDescr =~ s/\</\[LT\]/g;
				    	$ifDescr =~ s/\>/\[GT\]/g;
				    	$ifDescr =~ s/\./\[DOT\]/g;
				    	$ifDescr =~ s/\!/\[XCLM\]/g;
				    	$ifDescr =~ s/\@/\[AT\]/g;
				    	$ifDescr =~ s/\#/\[PND\]/g;
				    	$ifDescr =~ s/\$/\[DLLR\]/g;
				    	$ifDescr =~ s/\%/\[\PRCNT\]/g;
				    	$ifDescr =~ s/\^/\[CRT\]/g;
		
					if ( -e "$rrd_store/$device_name-$ifDescr.rrd") {
					# Uh, hey, it's there. Don't worry, be happy.
					}
					else {  # Oh, damn, it isn't, better create it.
				
			# Knowing the speed of the interface, generally reported by SNMP in bits per second,
			# we can fairly accurately determine how long it could take that counter to roll over,
			# if it's a 32 bit counter.
			# So, we'll use that info in creating the interface data. You may recognize these variables
			# from the RRD tutorial docs, which were further derived from MRTG. I reuse them both because
			# I'm lazy and so people will recognize what to hack on if they've beat up MRTG before.

						if ($speed = $data{$device_name}{$ifIndex}{'ifSpeed'}) {
							print "$device_name: Found $speed speed for $ifIndex\n";
						}
						else {
							$speed = "U";
						}
	
						@interface_rrd = (
						"DS:InBits:COUNTER:600:0:$speed",
						"DS:OutBits:COUNTER:600:0:$speed",
						"RRA:AVERAGE:0.5:1:600",
						"RRA:AVERAGE:0.5:6:700",
						"RRA:AVERAGE:0.5:24:775",
						"RRA:AVERAGE:0.5:288:797",
						"RRA:MAX:0.5:1:600",
						"RRA:MAX:0.5:6:700",
						"RRA:MAX:0.5:24:775",
						"RRA:MAX:0.5:288:797"
						);
	
			# I feed the array to the create argument here, so it's easier to alter the rrd
			# creation by just changing entries in the array above. Generic and reusable.

						if(RRDs::create ("$rrd_store/$device_name-$ifDescr.rrd",
							 "--step=300", 
							 @interface_rrd)) {
							print "Built RRd for $ifDescr\n";
						}
						else {
							$ERR=RRDs::error;
							print "RRd build for $ifDescr appears to have failed: $ERR\n";
							next;
						}
					}


			# Do some calculations.

					$data{$device_name}{$ifIndex}{InBits} = $data{$device_name}{$ifIndex}{ifInOctets} * 8;
					$data{$device_name}{$ifIndex}{OutBits} = $data{$device_name}{$ifIndex}{ifOutOctets} * 8;

			# Feed the RRD our data.

					$rrdfeed = join ":", ("N", 
						$data{$device_name}{$ifIndex}{InBits},
#      		                          	$data{$device_name}{$ifIndex}{IfInErrors},
       		                         	$data{$device_name}{$ifIndex}{OutBits},
#      		                          	$data{$device_name}{$ifIndex}{IfOutErrors},
					);

					RRDs::update ("$rrd_store/$device_name-$ifDescr.rrd",
						"--template", "InBits:OutBits", 
						"$rrdfeed"); 

					if($ERR=RRDs::error) {
						print STDERR "$rrd_store/$device_name-$ifDescr.rrd update failed: $ERR\n";
					}
					else {
						#print "$rrd_store/$device_name-$ifDescr.rrd updated\n" if ($debug);
					}
				}
			}	# yeah, it's sloppy, sue me.
        	}
        	else {
		# Abort abort abort, no go no go. uNF. =)
                	print STDERR "$device_name: SNMP Session failed: $error\n";
        	}
	}

	$end = time;

	$duration = $end - $start;
	$sleep_period = 300 - $duration;
	if($sleep_period > 0) { sleep($sleep_period) }
	undef(%data);
}
