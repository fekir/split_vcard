#!/usr/bin/perl
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  Copyright (C) 2012 Atul Talesara (atul@atult.net)
#  This software is licensed under the GPLv3 license
#   - atales 08/05/2012
#
#   Script to split single VCF file with multiple contacts into one file for each contact.
#   The file name is "Full Name" of the contact
#
#   Notes:
#    - The logic here is very simple.  Each vCard is demarcated by a "BEGIN:VCARD" and
#      "END:VCARD" tags.
#
#    - So we dump everything between these tags (inclusive) into its own individual vCard.
#
#    - Sample VCard Entry
#       BEGIN:VCARD
#       VERSION:3.0
#       N:;Voicemail;;;
#       FN:Voicemail
#       TEL;TYPE=WORK:86
#
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#   History
#   v0.1    - Beta Release
#               o Not tested with corrupt files
#
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#


#use strict;
use Getopt::Std;

#- - - - - - - - - - - - - - | Globals/Constants | - - - - - - - - - - - - - - - - - - - -
my $Verbosity               = 0;
my $Items_Processed         = 0;
my $Vcards_Processed        = 0;
my $Unnamed_Vcards          = 0;
my $Named_Vcards            = 0;
my $Incomplete_Vcards       = 0;
my $Unprocessed_Lines       = 0;
my $Cards_Made              = 0;

my $Debug_StopAfterEntries  = 0;

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# cmdline options
#   -i      -> Input VCF filename
#   -o      -> Output dir
#               All the individual vcf files go here
#   -v      -> verbosity level
getopts('i:o:v:');


# input parameters checking
if (!$opt_i) {
    usage("\nError! Input VCF filename missing,  -i\n");
    die;
}

my $input_file  = $opt_i;

if (!$opt_o) {
    usage("\nError! Output directory missing -o\n");
    die;
}

if (($opt_v) && ($opt_v >= 1) && ($opt_v <= 3)) {
    $Verbosity = $opt_v;
}

my $input_file  = $opt_i;
my $output_dir  = $opt_o;

print "
Parameters...
    Input VCF File      : $input_file
    Output Dir          : $output_dir
    Verbose Level       : $Verbosity
";

# Check the input file exists
if (!(-f $input_file)) {
    usage("\n Error: Input file missing: $input_file!\n");
    die;
}

# Check that output dir exists
if (!(-d $output_dir)) {
    usage("\n Error: Output directory doesn't exist: $output_dir!\n");
}

# Open input file
if (!open(INPUT_FILE, "$input_file")) {

    usage("\n Error: Opening input file missing: $input_file!\n");
}

if ($Debug_StopAfterEntries > 0){

    print"\n WARN: Would break after processing $Debug_StopAfterEntries entries...\n";
}

my $line            = "";
my $temp_line       = "";
my $single_vcard    = "";
while ($line = <INPUT_FILE>) {

    if ($Verbosity >= 2) {
        print "line: $line";
    }

    # If we are at the start of VCard
    #   - dump everything in separate file until we find end of this VCard
    #
    if ($line =~ m/^BEGIN:VCARD/) {

        $Vcards_Processed++;

        # clear hold buffer and found_name vars
        $single_vcard       = $line;
        my $found_name      = 0;        # whether we found an empty/non-empty name
        my $entry_unnamed   = 0;        # whether full name is empty
        my $found_endofcard = 0;        # reached end of Vcard
        my $process_entry   = 1;        # We should process the entry
        my $full_name       = "";       # the full name

        # Keep reading till we find the name
        # Save whatever we read as part of single vcard
        while ($temp_line = <INPUT_FILE>) {

            $single_vcard   .= "$temp_line";
            chomp($temp_line);

            if ($Verbosity >= 2) {
                print "temp_line: $temp_line";
            }

            # If I find the end, END:VCARD, before I find the name, that means
            # I have an incomplete vcard!
            if ($temp_line =~ m/^END:VCARD/) {

                $found_endofcard = 1;
                last;
            }

            # If we find an empty name entry, we need to a fake name for this entry
            if ($temp_line =~ m/^FN:$/) {

                $Unnamed_Vcards++;
                $entry_unnamed = 1;
                $found_name = 1;

                # Assign fake full name
                $full_name = sprintf "ZZZ_Unnamed_%04d", $Unnamed_Vcards;

            } elsif ($temp_line =~ m/^FN:/) {

                # If find name entry
                $Named_Vcards++;
                $found_name = 1;

                # Record the full name.  We will device destination single Vcard
                # file name from this full name.
                $full_name = $temp_line;
            }
        }

        # Result Table:
        #   Name Found | End Of Card |   Result
        # -------------+-------------+------------------------------------------------
        #       0      |       0     |  Hit EOF, incomplete Vcard and invalid file
        #       0      |       1     |  Incomplete Vcard, invalid entry
        #       1      |       0     |  Hit EOF, incomplete vcard and invalid file
        #       1      |       1     |  Complete Vcard found

        if (($found_name == 0) &&
            ($found_endofcard == 0)) {

            $Incomplete_Vcards++;
            print "\nERROR: Most likely hit EOF, vcard/file seems invalid!\n";

        } elsif (($found_name == 0) &&
                 ($found_endofcard == 1)) {

            $Incomplete_Vcards++;
            print "\nERROR: Most likely hit EOF, mostly corrupt entry!\n";

        } elsif (($found_name == 1) &&
                 ($found_endofcard == 0)) {

            $Incomplete_Vcards++;
            print "\nERROR: Most likely hit EOF(found name), vcard/file seems invalid!\n";

        } elsif (($found_name == 1) &&
                 ($found_endofcard == 1)) {

            #  Mark that we need to process this entry
            $process_entry = 1;

            if (($entry_unnamed == 1) &&
                ($Verbosity >= 1)) {

                print "\nFollowing Vcard is unnamed!\n";
                print "$single_vcard";
                print "---------------------------\n";
            }
        }

        # If we are out of the while-loop and haven't found the name, it is
        # a fatal error.  Stop processing at this point.
        ##  if ($found_name = 0) {

        ##      print"\n Processed $Items_Processed entries...\n";
        ##      die "ERROR: Premature end of file! Last line read \"$temp_line\"";
        ##  }

        #  If don't need to process this entry, due to errors, go to next entry
        if ($process_entry == 0) {
            next;
        }

        #  Found a complete and well-formed entry.
        #  Create a new Vcard file (with filename derived from full name) and
        #  dump the single vcard entry into it.
        $Items_Processed++;

        $vcard_fname = make_filename($full_name, $output_dir);
        #print "vcard filename = $vcard_fname\n";

        # Make the card now!!!
        make_vcard($vcard_fname, $single_vcard);
        $Cards_Made++;

    } else  {

        # All entries are back to back.  If we are here, that means we won't
        # process this line!!!!
        print "WARN: Cannot process this input line: $line";

        $Unprocessed_Lines++;

    }

    #  Check if we want to break after processing certain number of entries.
    #  Mostly used for debugging purposes.
    if (($Debug_StopAfterEntries > 0) &&
        ($Items_Processed >= $Debug_StopAfterEntries)) {

        print"\n Debug-Breaking after processing $Items_Processed entries...\n";
        last;

    }
}
close INPUT_FILE;

print"\n Done Processing:
    VCards              = $Vcards_Processed
    Processed           = $Items_Processed
    Named Cards         = $Named_Vcards
    Incomplete Cards    = $Incomplete_Vcards
    Unprocesses Lines   = $Unprocessed_Lines
    Unnamed Cards       = $Unnamed_Vcards;
    Card Files created  = $Cards_Made\n";

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
#  Make a filename derived out of input string given to me.
#
sub make_filename {

    # Exactly one parameter only.
    if (@_ != 2) {
        print "WARNING! &make_filename should get exactly two arguments!\n";
        return;
    }

    my ($input, $dir)    = @_;

    # replace all illegal characters with '_'
    my $fname = $input;
    my $test_fname = "";

    $fname =~ s/^FN://g;
    #$fname =~ s/[*()%!;\.\-\#\?@\s]/_/g;
    $fname =~ s/[^a-zA-Z0-9_]/_/g;

    # Append a VCF to filename and see if that file already exists
    # If it does, add a suffix
    $test_fname = "$output_dir/" . $fname . ".vcf";

    if (-e $test_fname) {
        print "\nWARN: $test_fname exists!";

        my $rand_num = int(rand(101));

        # Add random number as suffix
        $test_fname = "$output_dir/" . $fname . "_$rand_num" . ".vcf";
        print "  Using $test_fname";
    }

    $fname = $test_fname;

    if (-e $fname) {
        print "\nWARN: Opps, this is unexpected $fname exists too!";
        return int(rand(9999));
    }
    
    return $fname;
}

#  dump the contents of given vcard in given filename
#
sub make_vcard {

    # Exactly one parameter only.
    if (@_ != 2) {
        print "WARNING! &make_vcard should get exactly two arguments!\n";
        return;
    }

    my ($fname, $contents)    = @_;

    open VCARD_OUT, ">", "$fname" or die $!;

    print VCARD_OUT $contents;
    close VCARD_OUT;
}

#   Print tool usage help
#
sub usage {

    # Exactly one parameter only.
    if (@_ >= 1) {
        my ($msg)   = @_;
        print $msg;
    }

    print"
Usage: perl split_vcf.pl -i input_file -o output_dir [OPTION]

    -v,         Verbosity levels, 1-3

";
}
