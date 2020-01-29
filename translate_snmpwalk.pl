#!/usr/bin/env perl
#
# Copyright (C) 2019 Keith Sinclair <keith@sinclair.org.au>
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;

# change this if you don't store the file here.
my $oidfile = "/usr/local/mibs/mibs.oid";
my $enterprisePrefix = "1.3.6.1.4.1";
my $stardardPrefix = "1.3.6.1.2";
my $snmpV2Prefix = "1.3.6.1.6";
my $needsTranslate = qr/(SNMPv2-SMI::enterprises.\d+|DPS-MIB-V38::dpsAlarmControl.\d+|SNMPv2-SMI::mib-2.\d+|SNMPv2-SMI::snmpModules.\d+)/;

&main;


exit 0;

sub help {
        print <<EO_TEXT;
$0 will load an SNMPWALK file and translate any OID's it can to text.

EO_TEXT
}

sub main {

	if ( $ARGV[0] =~ /\/help|\-help|\-h/ ) { 
        help;
        exit 1;
	}
	elsif ( not defined $ARGV[0] ) { 
        help;
        print "ERROR: $0 needs to know a file to process\n";
        print "usage: $0 <snmpwalkfile.mib>\n";
        print "eg: $0 Cisco_Router.mib\n";
        exit 1;
	}

	# must have a file now?
	my $file = $ARGV[0];

	# is it readable?
	if ( -r $file ) {
		# great, load the mibs into memory
		my $mibs = loadOidIndex();
		my $translated = 0;
		my $lines = 0;

		#SNMPv2-SMI::enterprises.14706.1.1.4.1.5.1 = INTEGER: 1
		#compile the regex so it is super fast
		

		open (IN, $file) or die "Cannot open $file. $!";
		while (<IN>) {
			++$lines;
			chomp;

			#get the OID into a variable
			my ($oid,$rest) = split(" = ",$_);

	        if ( $oid =~ /$needsTranslate/ ) {
				my $oidTranslated = 0;

				# get partial translated back to full OID
				$_ =~ s/SNMPv2-SMI::enterprises/1.3.6.1.4.1/g;
				$oid =~ s/SNMPv2-SMI::enterprises/1.3.6.1.4.1/g;

				# handling the DPS-MIB-V38::dpsAlarmControl MIB
				$_ =~ s/DPS-MIB-V38::dpsAlarmControl/1.3.6.1.4.1.2682.1/g;
				$oid =~ s/DPS-MIB-V38::dpsAlarmControl/1.3.6.1.4.1.2682.1/g;

				$_ =~ s/SNMPv2-SMI::mib-2/1.3.6.1.2.1/g;
				$oid =~ s/SNMPv2-SMI::mib-2/1.3.6.1.2.1/g;

				$_ =~ s/SNMPv2-SMI::snmpModules/1.3.6.1.6.3/g;
				$oid =~ s/SNMPv2-SMI::snmpModules/1.3.6.1.6.3/g;

				# the oid finishes in something other than 0, probably a simple table index.
				if ( $oid =~ /\.\d+$/ ) {
					$oid =~ s/\.\d+$//;
					if ( defined $mibs->{$oid} and $mibs->{$oid} ne "" ) {
					}
				}

				# so the oid must end in a complicated index, e.g. 
				# 1.3.6.1.4.1.3375.2.2.14.6.3.1.30.16.47.67.111.109.109.111.110.47.76.83.78.95.80.111.111.108
				# "ltmLsnPoolStatTotalPortBlockDeallocations"			"1.3.6.1.4.1.3375.2.2.14.6.3.1.30"
				if ( not $oidTranslated ) {
					# keep processing the oid till it gets to the Enterprise
					# stop processing when we get to the enterprise prefix.
					while ( $oid ne $enterprisePrefix and $oid ne "SNMPv2-SMI::enterprises" ) {
						$oid = shortenOid($oid);
						if ( defined $mibs->{$oid} and $mibs->{$oid} ne "" ) {
							$oidTranslated = 1;
							$_ =~ s/$oid/$mibs->{$oid}/;
							last;
						}
					}
				}

				if ( $oidTranslated ) {
					++$translated;
					print "$_\n";
				}
				else {
					# this means missing a MIB or not handling the index yet.
					print "NEEDS TRANSLATE: $_\n";
				}
			}
	        elsif ( $oid =~ /$stardardPrefix|$snmpV2Prefix|$enterprisePrefix/ ) {
	        	# remove the leading . from the oid
	        	$oid =~ s/^\.//;
				my $oidTranslated = 0;
				while ( $oid ne $stardardPrefix and $oid ne $snmpV2Prefix and $oid ne $enterprisePrefix ) {
					$oid = shortenOid($oid);
					if ( defined $mibs->{$oid} and $mibs->{$oid} ne "" ) {
						$oidTranslated = 1;
						$_ =~ s/$oid/$mibs->{$oid}/;
						# remove the leading . from the line.
						$_ =~ s/^\.//;
						last;
					}
				}
				if ( $oidTranslated ) {
					++$translated;
					print "$_\n";
				}
				else {
					# this means missing a MIB or not handling the index yet.
					print "NEEDS TRANSLATE: $_\n";
				}

			}
			else {
				print "$_\n";
			}
		}   
		print "$lines lines processed, $translated lines translated\n";     
	}
	else {
		print "ERROR, problem with $file, can not read it.\n";
	}
}

sub shortenOid {
	my $oid = shift;
	$oid =~ s/\.\d+$//;
	return $oid;
}

sub loadOidIndex {
	my %mibs;
	
	# is it readable?
	if ( -r $oidfile ) {
		#compile the regex so it is super fast
		my $oidqr = qr/"([\w\-\#]+)"\s+"([0-9.]+)"/;

        open (IN, $oidfile) or die "Cannot open $oidfile. $!";
        while (<IN>) {
        	chomp;
        	if ( $_ =~ /$oidqr/ ) {
        		$mibs{$2} = $1;
        	}
        	else {
        		print "Problem with regex-fu: $_\n";
        	}
        }        
    }
    else {
    	print "ERROR, problem with $oidfile, can not read it.\n";
    }

    # returning a reference to the data.
    return \%mibs;
}
