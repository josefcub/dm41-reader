#!/usr/bin/perl -w
#=[ Alpha ]===================================================================
#
# dm41.pl - Provide routines for generating and altering memory maps suitable
#           for loading into a SwissMicros DM-41 calculator.
#
# Usage: $ dm41.pl [options]
#
#  --filename	-f	File to read containing an existing memory dump
#  --help	-h	This helpful text
#  --inject     -i      Inject hexadecimal program dump into memory dump
#  --print      -p      Print out a memory dump after any other operations
#                       have been performed
#  --summary    -s      Display summary of information contained in the dump
#
# Notes:
#
# History:
#
#=============================================================================

#=====================================
# Required Perl Modules
#=====================================

# If a module doesn't exist on your system, this article:
#
# http://stackoverflow.com/questions/2980297/how-can-i-use-cpan-as-a-non-root-user
#
# will show you how to get cpanm working properly.  I also recommend adding:
#
# alias cpanm='perl /home/yourusername/perl5/bin/cpanm'
#
# to your .bashrc for ease-of-installing future modules.

use feature qw{ switch };
use strict;
use warnings;
use utf8;
use Getopt::Long;
use Time::Local;
use Data::Dumper;
use Encode;
use POSIX;

# For newer Perl, silencing some obnoxious warnings.
no if $] >= 5.018, warnings => "experimental::smartmatch";

#=====================================
# Configurable Variables
#=====================================

# Global configuration options
my $model_name =	"DM41";
my $MemorySize =	7784;

#=============================================================================
# Barring modifications, you should not need to change anything below here.
#=============================================================================

# Command line parameters
my $fname;        # The memory dump to read.
my $inject;
my $list;         # Program to list out.
my $print;				# Do we print out the memory dump?
my $summary;			# Do we want to print out a summary?
my $help;         # Display helpful text.

# Empty string definitions for the perl critic.
my $EMPTY =			"";

# Memory and CPU register contents.
my @memory	= (0) x $MemorySize;
my @cpuregisters = (0) x 6;


#=====================================
# Initialization and Preflight
#=====================================

GetOptions(
  'filename|f=s'	=> \$fname,
  'list|l=s'      => \$list,
  'print|p'       => \$print,
  'help|h'        => \$help,
  'summary|s'     => \$summary,
  'inject|i=s'    => \$inject,
) || printUsage();

# Because we use unicode to display some HP-41C characters.
binmode STDOUT, 'encoding(utf8)';
binmode STDIN, 'encoding(utf8)';
# We initialize a basic memory map in the absence of any other.
# Memory should have a few things in it by default.  This saves
# us from having to specify a filename, and provides quick and
# easy blank printed memory dumps.  This only happens when a
# filename is not specified with -f.
if (!$fname) {

  @memory = saveregister(84, "1000000000019c", @memory);
  @memory = saveregister(91, "1a70016919c19b", @memory);
  @memory = saveregister(98, "0000002c048020", @memory);
  @memory = saveregister(2877, "00000000c00020", @memory);

   $cpuregisters[0] = "00000000000000";
   $cpuregisters[1] = "00000000000000";
   $cpuregisters[2] = "00000000000000";
   $cpuregisters[3] = "00000000000000";
   $cpuregisters[4] = "00000000000000";
   $cpuregisters[5] = "00";

}

#=====================================
# Subroutines
#=====================================

######
#
# printUsage - Prints out helpful text.
#
######
sub printUsage {

  my $name = $0;
  print << "ENDUSAGE";

Usage: $name [options] -f <filename>

	--filename   -f   File to read containing an existing memory dump
	--help	     -h	  This helpful text
	--inject     -i   Inject program bytecode into memory map.
	--print      -p   Print out a memory dump after any other operations
			  have been performed
	--summary    -s   Display summary of information contained in the dump

Notes

     This script will generate a blank memory map, with just the bare minimum
required data, if no --filename is specified.  This is probably not what you want,
however, and we recommend using an external dump for analysis and manipulation.

ENDUSAGE

  exit 0;

}


######
#
# saveregister - Save a text register into the memory array starting
#                at the provided memory location.
#
######
sub saveregister {

  my ($location, $register, @dump) = @_;

  if ( $register !~ /([a-fA-F0-9]{2})([a-fA-F0-9]{2})([a-fA-F0-9]{2})([a-fA-F0-9]{2})([a-fA-F0-9]{2})([a-fA-F0-9]{2})([a-fA-F0-9]{2})/ ) {
    die "FATAL: Malformed register data encountered:\n       Register "
        . sprintf("%x", $location / 7) . " was $register.\n";
  } else {

    $dump[$location] = hex $1;
    $dump[$location + 1] = hex $2;
    $dump[$location + 2] = hex $3;
    $dump[$location + 3] = hex $4;
    $dump[$location + 4] = hex $5;
    $dump[$location + 5] = hex $6;
    $dump[$location + 6] = hex $7;

  }

  return @dump;
}

######
#
# loadfile - Parse and load a DM-41 dump file's contents
#            into the memory array.
#
######
sub loadfile {

  my $filename 	= shift;
  my $model		= "";
  my @dump 		= (0) x $MemorySize;
  my @dumpregs 	= (0) x 6;

  open( my $fh, '<', $filename ) or die "Can't open $filename: $!";

  # read the file from top to bottom
  while (my $line = <$fh>) {

    chomp $line;

    # Puzzle out the different types of data we need.
    given ( $line ) {

      # Emulated CPU registers
      when (/A: ([a-fA-F0-9]{14})  B: ([a-fA-F0-9]{14})  C: ([a-fA-F0-9]{14})/) {
        $dumpregs[0] = $1;
        $dumpregs[1] = $2;
        $dumpregs[2] = $3;
      }

      # The other emulated CPU registers
      when (/M: ([a-fA-F0-9]{14})  N: ([a-fA-F0-9]{14})  G: ([a-fA-F0-9]{2,14})/) {
        $dumpregs[3] = $1;
        $dumpregs[4] = $2;
        $dumpregs[5] = $3;
      }

      # Actual memory contents
      when (/([a-fA-F0-9]{1,3})  ([a-fA-F0-9]{14})  ([a-fA-F0-9]{14})  ([a-fA-F0-9]{14})  ([a-fA-F0-9]{14})/) {

        my $offset = (hex $1) * 7;

        @dump = saveregister ($offset, $2, @dump);
        @dump = saveregister ($offset + 7, $3, @dump);
        @dump = saveregister ($offset + 14, $4, @dump);
        @dump = saveregister ($offset + 21, $5, @dump);

     }

      # Four byte SwissMicros ID header
      when (/DM([0-9]{2})/) {
        $model = "$_";
      }

      # Empty whitespace lines
      when (/^\s*$/) {
      }

      # anything else ought to be an error.
      default {
        die "FATAL: Unhandled line: $_\n";
      }

    }

  }

  close $fh || die "Unable to close $filename after read, because $!";

  # There's more than one calculator that uses this format.
  if ( $model ne "DM41" ) {
    die "FATAL: This appears to be a memory dump for a $model.  Please \n       check your dump file and try again.\n";
  }

  # Simple sanity check.  $0D, bytes 3 and 4 contain the
  # calculator's watchdog constant, 0x0169.  If this is
  # not present, something is seriously wrong with this
  # dump, and the user should be warned.
  my $watchdog = (($dump[93] & 15) * 256) + $dump[94];
  if ( $watchdog != 361 ) {
    print "WARNING: The calculator's watchdog word in register 0x0D is invalid.  It\n";
    print "         contains $watchdog instead of 361 (0x169).  The DM-41 will show\n";
    print "         MEMORY LOST and no data if this file is uploaded as-is.  Please\n";
    print "         check your memory dump for corruption before using this output.\n\n";
  }

  return (@dumpregs, @dump);
}

######
#
# printfile - Prints out a memory dump based on the current contents of memory.
#
######
sub printfile {

  my @dumpregs = (0) x 6;
  my @dump = (0) x $MemorySize;

  # Pull in all of the required data.
  (
    $dumpregs[0],
    $dumpregs[1],
    $dumpregs[2],
    $dumpregs[3],
    $dumpregs[4],
    $dumpregs[5],
    @dump,
  ) = @_;

  print "$model_name\n";

  # Assemble one line from the memory array.
  for (my $offset = 0; $offset < 512; $offset = $offset + 4) {

    my $line = sprintf("%0.2x", $offset) . "  ";

    for (my $a = 0; $a < 4; $a++) {

      # Assemble one register and prepare it for printing
      for (my $b = 0; $b < 7; $b++) {

        $line = $line . sprintf("%0.2x", @dump[($offset * 7) + ($a * 7) + $b]);

      }

      $line = $line . "  ";
    }

    $line = $line . "\n";

    # If the four registers we want to print are all empty, don't bother printing it.
    if ($line !~ /([a-fA-F0-9]{2,4})  00000000000000  00000000000000  00000000000000  00000000000000/) {
      print $line;
    }

  }

  # Print the CPU registers as they are.
  print "A: $dumpregs[0]  B: $dumpregs[1]  C: $dumpregs[2]\n";
  print "M: $dumpregs[3]  N: $dumpregs[4]  G: $dumpregs[5]\n\n";

  # Simple sanity check.  $0D, bytes 3 and 4 contain the
  # calculator's watchdog constant, 0x0169.  If this is
  # not present, something is seriously wrong with this
  # dump, and the user should be warned.
  my $watchdog = (($dump[93] & 15) * 256) + $dump[94];
  if ( $watchdog != 361 ) {
    print "WARNING: The calculator's watchdog word in register 0x0D is invalid.  It\n";
    print "         contains $watchdog instead of 361 (0x169).  The DM-41 will show\n";
    print "         MEMORY LOST and no data if this file is uploaded as-is.  Please\n";
    print "         check your memory dump for corruption before using this output.\n\n";
  }

  return;
}

######
#
# nextbyte - Provide the next byte in the memory map.  The HP-41C
#            series reads program registers starting at the -top- of RAM
#            downward, but reads the instructions from the -bottom- of
#            the register upward.  This provides a convenient mechanism
#            to point to the next RAM location needed, in program order.
#
######
sub nextbyte {

  my $location = shift;

  # Where are we in the register?
  my $offset = int $location % 7;

  # Moving backwards instead of forward seems
  # to be absurd.
  if ( $offset == 6 ) {
    $location = $location - 13 ;
  } else {
    $location++;
  }

  return $location;

}

######
#
# alphatranslate - Translate 41C letters up to UTF-8 standards.
#
######
sub alphatranslate {

  my $value = shift;

  given (ord $value) {

    when (13) { $value = "∡"; }
    when (46)  { $value = "≻"; }
    when (126) { $value = "Σ"; }
    when (127) { $value = "⊢"; }
    default { }

  }

  return $value;

}

######
#
# find_programs - Show all the programs and their byte sizes in a
#                 given memory map.
#
######
sub find_programs {

  my @dump = (@_);

  my $programsizecounter  = 0;	# For calculating the end
  my $totallabels         = 0;	# Number of global labels
  my $totalprograms       = 0;	# Total number of programs
  my $numlabels           = 0;  # Number of labels in a program
  my @programlist;				      # List of LBLs and sizes.

  # Calculate where the programs lie in the memory space, based on
  # the status register 0x0D.  Byte 95 and the top nybble of 96
  # make up the program space's top.  The bottom nybble of 96 and
  # all of 97 make up the end of the program space.
  my $program_top = ($dump[95] * 16) + ($dump[96] >> 4) - 1;
  my $program_limit = (($dump[96] & 15) * 256) + $dump[97];

  # Search the user program memory range, in register order, for LBL
  # instructions, indicating a global subroutine or program label.
  for (my $i = ($program_top) * 7; $i >= $program_limit * 7; $i = nextbyte $i) {

    my $next			= nextbyte $i;				# For going forward
    my $next2			= nextbyte nextbyte $i;		# END and LBL are 3 byte

    # For assembling label names.
    my $label = "";
    my $labelbytes = nextbyte $next2;

    # Irrelevant multibyte instructions - 9/A/B
    if ($dump[$i] >> 4 > 8 && $dump[$i] >> 4 < 12) {
      $i = nextbyte $i;
      next;
    }

    # Handle irrelevant multibyte instructions - D/E
    if ($dump[$i] >> 4 > 12 && $dump[$i] >> 4 < 15) {
      $i = nextbyte nextbyte $i;
      next;
    }

    # Find GLOBAL bytes
    if ($dump[$i] >> 4 == 12 && ($dump[$i] & 15) <= 13) {

      # Is it a label?
      if ($dump[$next2] >= 240) {

        # For those of us keeping count, correct the first
        # byte count on the first program.
        if ( $totallabels == 0 ) { $programsizecounter = 3; }
        $totallabels++;

        # Pull out and display the key assignment and LBL instruction's text.
        for (my $i = 0; $i < $dump[$next2] - 240; $i++) {

          # Key assignment, if applicable.
          if ($i == 0) {
            $labelbytes = nextbyte $labelbytes;
            next
          };

          # Provides fixes for HP-41C special characters.  Maps to
          # UTF-8.
          $label = $label . alphatranslate(chr $dump[$labelbytes]);
          $labelbytes = nextbyte $labelbytes;

        }

        push @programlist, "  LBL \"$label\"";

      # If it's not a label, it's an END.
      } else {
          if (($dump[$next2] & 32) == 32) {
            # .END. found, don't add to the list.
        } else {

          $totalprograms++;

          push @programlist,  $programsizecounter; # . sprintf(" %0.2x%0.2x%0.2x", $dump[$i], $dump[$next], $dump[$next2]);

          $programsizecounter = 0;

        }
      }

    }

    # increment the byte counter
    $programsizecounter++;

  }

  # $totalprograms--;
  unshift @programlist, $totallabels, $totalprograms;
  return @programlist;

}

######
#
# find_alarms - Find and return the alarms and alarm text.
#
######
sub find_alarms {

  my @dump = (@_);

  # Calculate where the alarms may lay in memory space.  This is -lower-
  # than any programs currently written.
  my $program_limit = (($dump[96] & 15) * 256) + $dump[97];

  my $alarm_start = 0;     # Starting register for alarm partition
  my $alarm_limit = 0;     # Number of alarm registers total
  my $alarm_count = 0;     # Total number of alarms
  my @alarms;              # For returning alarm data

  # Search the assignment and alarm partition for the start
  # of alarm space.
  for (my $i = 192; $i < $program_limit; $i++) {

    if ( $dump[$i * 7] == 170 ) {
      $alarm_start = $i;
      $alarm_limit = $dump[($i * 7) + 1];
      last;
    }

  }

  # No alarm partition, no alarms defined.
  if ($alarm_start == 0) { return 0; }

  # Find the registers I need for the name of an alarm
  for (my $i = $alarm_start + 1; $i < $alarm_start + $alarm_limit - 1;) {

    # The time is kept on the calculator in -BCD-, and counts tenths of seconds
    # from January 1, 1900.  We need to fix this so that we can use our built-
    # in epoch functions.  2208988800 is the number of seconds between the
    # aforementioned date and the start of the Unix epoch.
    my $alarm_time = (int sprintf("%0x%0.2x%0.2x%0.2x%0.2x%x", ($dump[($i * 7) + 0]), ($dump[($i * 7) + 1]), ($dump[($i * 7) + 2]), ($dump[($i * 7) + 3]),($dump[($i * 7) + 4]),($dump[($i * 7) + 5] >> 4)) / 10) - 2208988800;

    # Time on calculator is assumed to be UTC by the system.  I need a whole
    # perl module for this.  Ugh.
    my $tzoffset = abs timegm(localtime) - timelocal(localtime);
    $alarm_time += $tzoffset;

    # Prepare numbers for crunching.  Helpful, I know.
    my $numregs = $dump[($i * 7) + 6] & 15;
    my $repeating = $dump[($i * 7) + 5] & 15;
    my $repeat_interval = 0;
    my $interval = 0;
    my $alarm_name = "";

    # We're looking for 0xF0 to mark the end of alarm space.
    # If we find it, we should stop parsing alarms entirely.
    if ($dump[$i * 7] != 240) {

      $alarm_count++;

    } else {

      # no alarms found.
      return 0;

    }

    if ( $repeating == 1 ) {

      $i++;

      $repeat_interval = int sprintf("%0x%0.2x%0.2x%x", ($dump[($i * 7) + 2]), ($dump[($i * 7) + 3]), ($dump[($i * 7) + 4]), ($dump[($i * 7) + 5] >> 4)) / 10;

    }

    $i++;

    # If there's message text, let's spend the time decoding it.
    if ($numregs > 0) {

      # Let's parse out the message text
      for (my $j = $i * 7; $j < ($i + $numregs) * 7; $j++) {

        my $datum = $dump[$j];
        if ($datum > 00) {
          $alarm_name = $alarm_name . chr($datum);
        }

      }

      $i = $i + $numregs;

    } else {

      $alarm_name = "ALARM";

    }

    push @alarms, $alarm_time, $repeating, $repeat_interval, $alarm_name;


  }

  unshift @alarms, $alarm_count;

  return @alarms;

}

######
#
# dump_summary - Display summary information derived from the memory dump.
#
######
sub dump_summary {

  my @dump = (@_);
  my ($labels,
      $programs,
      @programlist) = find_programs(@dump);

  # Let's print a list of programs.

  if ( $programs > 0 ) {
    print "\n  Programs                              Size\n";
    print "---------------------------------------------------";

    for my $i (0..$#programlist) {

      if ($programlist[$i] =~ /LBL/) {

        print sprintf("\n%-30s        | ", $programlist[$i]);

      } else {

        print sprintf("%3s%6s", $programlist[$i], " bytes\n---------------------------------------------------");

      }

    }

  print "\n";

  } else {
    print "\n  No programs found in memory.\n";
  }

  # Let's do a list of alarms next.
  my ($alarm_count,
      @alarms) = find_alarms(@dump);

  if ($alarm_count > 0) {
    print "\n  Alarms            Time                Interval\n";
    print "---------------------------------------------------\n";

    for (my $i = 0; $i < $#alarms; $i = $i + 4) {


      my $alarm_time = $alarms[$i];
      my $alarm_repeating = $alarms[$i + 1];
      my $alarm_interval = $alarms[$i + 2];
      my $alarm_name = $alarms[$i + 3];

      print sprintf("  %-16s| ", $alarm_name);
      print sprintf("%17s | ", POSIX::strftime("%D %T", localtime($alarm_time)));

      if ( $alarm_repeating > 0 ) {

        # Break this into something readable.
        my $days = int $alarm_interval/86400;
        my $hours = ($alarm_interval/3600)%24;
        my $minutes = ($alarm_interval/60)%60;
        my $seconds = $alarm_interval%60;

        print sprintf("%0.2d %0.2d:%0.2d:%0.2d\n", $days, $hours, $minutes, $seconds);
      } else {
        print "-- --------\n";
      }

    }

    print "---------------------------------------------------\n";

  } else {
    print "\n  No alarms found in memory.\n";
  }

  # Calculate where the programs lie in the memory space, based on
  # the status register 0x0D.  Byte 95 and the top nybble of 96
  # make up the program space's top.  The bottom nybble of 96 and
  # all of 97 make up the end of the program space.
  my $program_top = ($dump[95] * 16) + ($dump[96] >> 4) - 1;
  my $program_limit = (($dump[96] & 15) * 256) + $dump[97];

  # Calculate the number of main RAM registers remaining, by searching for
  # the last register beginning with F0, between the bottom of RAM and the
  # bottom .END..  This indicates the last alarm or key assignment register.
  my $program_bottom = $program_limit ;
  for (my $i = $program_limit - 1; $i >= 192; $i = $i - 1) {

    # Hex value 0xF0 marks the bottom of the space we can use
    # to add programs.  This marker actually moves around!
    if ( $dump[$i * 7] == 240 ) {
      last;
    }

    $program_bottom--;

  }

  # Show basic statistics summary about the memory dump.

  print "\n      Total                       Registers\n";
  print "---------------------------------------------------\n";

  # Include key assignment and alarm space in the number from program sizes.
  print sprintf("%8s Program(s)%18s Used\n", $programs, ($program_top - $program_limit) + ($program_bottom - 192));
  print sprintf("%8s Label(s)  %18s Storage\n", $labels, (511 - $program_top));
  print sprintf("%8s Alarm(s)  %18s Free\n\n", $alarm_count, ($program_limit - $program_bottom));

}
#####
#
# xrom_translate = Take i, j and return string of function call.
#
#####
sub xrom_translate {

  my ($i, $j) = @_;

  # I'm only going to cover the CX modules here.
  given ($i) {
    # CX X Functions
    when (25) {
      given ($j) {
        when (1) { return "ALENG"; }
        when (2) { return "ANUM"; }
        when (3) { return "APPCHR"; }
        when (4) { return "APPREC"; }
        when (5) { return "ARCLREC"; }
        when (6) { return "AROT"; }
        when (7) { return "ATOX"; }
        when (8) { return "CLFL"; }
        when (9) { return "CLKEYS"; }
        when (10) { return "CRFLAS"; }
        when (11) { return "CRFLD"; }
        when (12) { return "DELCHR"; }
        when (13) { return "DELREC"; }
        when (14) { return "EMDIR"; }
        when (15) { return "FLSIZE"; }
        when (16) { return "GETAS"; }
        when (17) { return "GETKEY"; }
        when (18) { return "GETP"; }
        when (19) { return "GETR"; }
        when (20) { return "GETREC"; }
        when (21) { return "GETRX"; }
        when (22) { return "GETSUB"; }
        when (23) { return "GETX"; }
        when (24) { return "INSCHR"; }
        when (25) { return "INSREC"; }
        when (26) { return "PASN"; }
        when (27) { return "PCLPS"; }
        when (28) { return "POSA"; }
        when (29) { return "POSFL"; }
        when (30) { return "PSIZE"; }
        when (31) { return "PURFL"; }
        when (32) { return "RCLFLAG"; }
        when (33) { return "RCLPT"; }
        when (34) { return "RCLPTA"; }
        when (35) { return "REGMOVE"; }
        when (36) { return "REGSWAP"; }
        when (37) { return "SAVEAS"; }
        when (38) { return "SAVEP"; }
        when (39) { return "SAVER"; }
        when (40) { return "SAVERX"; }
        when (41) { return "SAVEX"; }
        when (42) { return "SEEKPT"; }
        when (43) { return "SEEKPTA"; }
        when (44) { return "SIZE?"; }
        when (45) { return "STOFLAG"; }
        when (46) { return "X<>F"; }
        when (47) { return "XTOA"; }
        when (49) { return "ASROOM"; }
        when (50) { return "CLRGX"; }
        when (51) { return "ED"; }
        when (52) { return "EMDIRX"; }
        when (53) { return "EMROOM"; }
        when (54) { return "GETKEYX"; }
        when (55) { return "RESZFL"; }
        when (56) { return "ΣREG?"; }
        when (57) { return "X=NN?"; }
        when (58) { return "X#NN?"; }
        when (59) { return "X<NN?"; }
        when (60) { return "X≤NN?"; }
        when (61) { return "X>NN?"; }
        when (62) { return "X≥NN?"; }
        default { return "XROM $i,$j"; }
      }
    }
    when (26) {
      given ($j) {
        when (1) { return "ADATE"; }
        when (2) { return "ALMCAT"; }
        when (3) { return "ALMNOW"; }
        when (4) { return "ATIME"; }
        when (5) { return "ATIME24"; }
        when (6) { return "CLK12"; }
        when (7) { return "CLK24"; }
        when (8) { return "CLKT"; }
        when (9) { return "CLKTD"; }
        when (10) { return "CLOCK"; }
        when (11) { return "CORRECT"; }
        when (12) { return "DATE"; }
        when (13) { return "DATE+"; }
        when (14) { return "DDAYS"; }
        when (15) { return "DMY"; }
        when (16) { return "DOW"; }
        when (17) { return "MDY"; }
        when (18) { return "RCLAF"; }
        when (19) { return "RCLSW"; }
        when (20) { return "RUNSW"; }
        when (21) { return "SETAF"; }
        when (23) { return "SETDATE"; }
        when (24) { return "SETSW"; }
        when (25) { return "STOPSW"; }
        when (26) { return "SW"; }
        when (27) { return "T+X"; }
        when (28) { return "TIME"; }
        when (29) { return "XYZALM"; }
        when (31) { return "CLALMA"; }
        when (32) { return "CLALMX"; }
        when (33) { return "CLRALMS"; }
        when (34) { return "RCLALM"; }
        when (35) { return "SWPT"; }
        default { return "XROM $i,$j"; }
      }
    }
    default { return "XROM $i,$j"; }

  }

return "XROM $i,$j";

}

######
#
# parse_memory - Given a memory location and a memory dump, return the
#                plain text of the instruction line found there.  This
#                should also return the hex bytes of the instruction
#                and a total count.
#
######
sub parse_memory {

  my ($location,
          @dump) = @_;

  my $instruction_hex = "";
  my $instruction_text = "";

  my $next = nextbyte $location;
  my $next2 = nextbyte nextbyte $location;


  given ($dump[$location]) {

    # 0x01 - 0x0F - LBL xx - One byte
    when ($_ > 0 && $_ < 0x10) {
      $instruction_hex = sprintf("%0.2x", $dump[$location]);
      $instruction_text = "LBL " . sprintf("%0.2d", ($dump[$location] & 15) - 1);
      $location = $next;
    }

    # 0x10 - 0x1A - Numbers and a period - Variable bytes.
    # Apparently, numbers in order are concatenated by
    # the calculator, including the period.
    when ($_ > 0x0f && $_ < 0x1B) {

      $instruction_hex = "";
      $instruction_text = "";
      my $pointer = $location;

      while ($dump[$pointer] > 0x0F && $dump[$pointer] < 0x1B) {
        $instruction_hex .= sprintf("%0.2x", $dump[$pointer]);
        given ($dump[$pointer]) {
          when (0x10) { $instruction_text .= "0"; }
          when (0x11) { $instruction_text .= "1"; }
          when (0x12) { $instruction_text .= "2"; }
          when (0x13) { $instruction_text .= "3"; }
          when (0x14) { $instruction_text .= "4"; }
          when (0x15) { $instruction_text .= "5"; }
          when (0x16) { $instruction_text .= "6"; }
          when (0x17) { $instruction_text .= "7"; }
          when (0x18) { $instruction_text .= "8"; }
          when (0x19) { $instruction_text .= "9"; }
          when (0x1A) { $instruction_text .= "."; }
        }
          $pointer = nextbyte $pointer;
      }

      $location = $pointer;
    }

    # 0x1D, 0x1E, 0x1F - GTO/XEQ/W - Many bytes
    when ($_ == 0x1D || $_ == 0x1E || $_ == 0x1F) {

      my $label;
      my $labelhex = sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);
      my $labelbytes = $next2;

      # Pull out and deliver the text field.
      for (my $i = 0; $i < $dump[$next] - 240; $i++) {
          # Provides fixes for HP-41C special characters.  Maps to
          # UTF-8.
          $label .= alphatranslate(chr $dump[$labelbytes]);
          $labelhex .= sprintf("%0.2x", $dump[$labelbytes]);
          $labelbytes = nextbyte $labelbytes;
      }

      given ($dump[$location]) {
        when (0x1D) { $instruction_text = "GTO \"" . $label . "\""; }
        when (0x1E) { $instruction_text = "XEQ \"" . $label . "\""; }
        when (0x1F) { $instruction_text = "W \"" . $label . "\"";  }
        default { $instruction_text = "BROKEN \""; }
      }

      $instruction_hex = $labelhex;
      $location = $labelbytes;

    }

    # 0x20 - 0x2F - RCL xx - One byte
    when ($_ >> 4 == 2) {
      $instruction_hex = sprintf("%0.2x", $dump[$location]);
      $instruction_text = "RCL " . sprintf("%0.2d", ($dump[$location] & 15));
      $location = $next;
    }

    # 0x30-0x3F - STO xx - One byte
    when ($_ >> 4 == 3) {
      $instruction_hex =  sprintf("%0.2x", $dump[$location]);
      $instruction_text = "STO " . sprintf("%0.2d", $dump[$location] & 15);
      $location = $next;
    }

    # This covers all single-byte instructions.  All of them.  No exceptions.
    # Except: 0x00 - NULL, 0x01-0x1F - LBL xx, 0x1D, E, F - GTO ", XEQ ", W ".
    # But all the rest!  NO EXCEPTIONS!
    # And we also handle 0x20-0x3F - RCL/STO separately.  So, exceptions.
    when ($_ >> 4 != 2 && $_ >> 4 != 3 && $_ > 0x0F && $_ < 0x90 && $_ != 0x1D && $_ != 0x1E && $_ != 0x1F) {

      $instruction_hex =  sprintf("%0.2x", $dump[$location]);

      given ($dump[$location]) {

        when (0x1B) { $instruction_text = "EEX"; }
        when (0x1C) { $instruction_text = "NEG"; }
        when (0x40) { $instruction_text = "+"; }
        when (0x41) { $instruction_text = "-"; }
        when (0x42) { $instruction_text = "*"; }
        when (0x43) { $instruction_text = "/"; }
        when (0x44) { $instruction_text = "X<Y?"; }
        when (0x45) { $instruction_text = "X>Y?"; }
        when (0x46) { $instruction_text = "X≤Y?"; }
        when (0x47) { $instruction_text = "Σ+"; }
        when (0x48) { $instruction_text = "Σ-"; }
        when (0x49) { $instruction_text = "HMS+"; }
        when (0x4A) { $instruction_text = "HMS-"; }
        when (0x4B) { $instruction_text = "MOD"; }
        when (0x4C) { $instruction_text = "\%"; }
        when (0x4D) { $instruction_text = "\%CH"; }
        when (0x4E) { $instruction_text = "P->R"; }
        when (0x4F) { $instruction_text = "R->P"; }
        when (0x50) { $instruction_text = "LN"; }
        when (0x51) { $instruction_text = "X^2"; }
        when (0x52) { $instruction_text = "SQRT"; }
        when (0x53) { $instruction_text = "Y^X"; }
        when (0x54) { $instruction_text = "CHS"; }
        when (0x55) { $instruction_text = "E^X"; }
        when (0x56) { $instruction_text = "LOG"; }
        when (0x57) { $instruction_text = "10^X"; }
        when (0x58) { $instruction_text = "E^X-1"; }
        when (0x59) { $instruction_text = "SIN"; }
        when (0x5A) { $instruction_text = "COS"; }
        when (0x5B) { $instruction_text = "TAN"; }
        when (0x5C) { $instruction_text = "ASIN"; }
        when (0x5D) { $instruction_text = "ACOS"; }
        when (0x5E) { $instruction_text = "ATAN"; }
        when (0x5F) { $instruction_text = "->DEC"; }
        when (0x60) { $instruction_text = "1/X"; }
        when (0x61) { $instruction_text = "ABS"; }
        when (0x62) { $instruction_text = "FACT"; }
        when (0x63) { $instruction_text = "X#0?"; }
        when (0x64) { $instruction_text = "X>0?"; }
        when (0x65) { $instruction_text = "LN1+X"; }
        when (0x66) { $instruction_text = "X<0?"; }
        when (0x67) { $instruction_text = "X=0?"; }
        when (0x68) { $instruction_text = "INT"; }
        when (0x69) { $instruction_text = "FRC"; }
        when (0x6A) { $instruction_text = "D->R"; }
        when (0x6B) { $instruction_text = "R->D"; }
        when (0x6C) { $instruction_text = "->HMS"; }
        when (0x6D) { $instruction_text = "->HR"; }
        when (0x6E) { $instruction_text = "RND"; }
        when (0x6F) { $instruction_text = "->OCT"; }
        when (0x70) { $instruction_text = "CLΣ"; }
        when (0x71) { $instruction_text = "X<>Y"; }
        when (0x72) { $instruction_text = "PI"; }
        when (0x73) { $instruction_text = "CLST"; }
        when (0x74) { $instruction_text = "R^"; }
        when (0x75) { $instruction_text = "RDN"; }
        when (0x76) { $instruction_text = "LASTX"; }
        when (0x77) { $instruction_text = "CLX"; }
        when (0x78) { $instruction_text = "X=Y?"; }
        when (0x79) { $instruction_text = "X#Y?"; }
        when (0x7A) { $instruction_text = "SIGN"; }
        when (0x7B) { $instruction_text = "X≤0?"; }
        when (0x7C) { $instruction_text = "MEAN"; }
        when (0x7D) { $instruction_text = "SDEV"; }
        when (0x7E) { $instruction_text = "AVIEW"; }
        when (0x7F) { $instruction_text = "CLD"; }
        when (0x80) { $instruction_text = "DEG"; }
        when (0x81) { $instruction_text = "RAD"; }
        when (0x82) { $instruction_text = "GRAD"; }
        when (0x83) { $instruction_text = "ENTER^"; }
        when (0x84) { $instruction_text = "STOP"; }
        when (0x85) { $instruction_text = "RTN"; }
        when (0x86) { $instruction_text = "BEEP"; }
        when (0x87) { $instruction_text = "CLA"; }
        when (0x88) { $instruction_text = "ASHF"; }
        when (0x89) { $instruction_text = "PSE"; }
        when (0x8A) { $instruction_text = "CLRG"; }
        when (0x8B) { $instruction_text = "AOFF"; }
        when (0x8C) { $instruction_text = "AON"; }
        when (0x8D) { $instruction_text = "OFF"; }
        when (0x8E) { $instruction_text = "PROMPT"; }
        when (0x8F) { $instruction_text = "ADV"; }

      }

      $location = $next;
    }

    # 0x90-0x9B - RCL/STO/ISG/DSE/VIEW/EREG - Two byte
    when ($_ > 0x8F && $_ < 0x9A) {

      $instruction_hex =  sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);

      given ($dump[$location]) {
        when (0x90) { $instruction_text = "RCL "; }
        when (0x91) { $instruction_text = "STO "; }
        when (0x92) { $instruction_text = "ST+ "; }
        when (0x93) { $instruction_text = "ST- "; }
        when (0x94) { $instruction_text = "ST* "; }
        when (0x95) { $instruction_text = "ST/ "; }
        when (0x96) { $instruction_text = "ISG "; }
        when (0x97) { $instruction_text = "DSE "; }
        when (0x98) { $instruction_text = "VIEW "; }
        when (0x99) { $instruction_text = "ΣREG "; }
      }

      if ($dump[$next] < 112) {
        $instruction_text .= sprintf("%0.2d", $dump[$next]);
      }

      if ($dump[$next] > 111 && $dump[$next] < 128) {
        given ($dump[$next]) {
          when (112) { $instruction_text .= "T"; }
          when (113) { $instruction_text .= "Z"; }
          when (114) { $instruction_text .= "Y"; }
          when (115) { $instruction_text .= "X"; }
          when (116) { $instruction_text .= "L"; }
          when (117) { $instruction_text .= "M"; }
          when (118) { $instruction_text .= "N"; }
          when (119) { $instruction_text .= "O"; }
          when (120) { $instruction_text .= "P"; }
          when (121) { $instruction_text .= "Q"; }
          when (122) { $instruction_text .= "⊢"; }
          when (123) { $instruction_text .= "a"; }
          when (124) { $instruction_text .= "b"; }
          when (125) { $instruction_text .= "c"; }
          when (126) { $instruction_text .= "d"; }
          when (127) { $instruction_text .= "e"; }
          default { $instruction_text = "INVALID"; }
        }
      }

      if ($dump[$next] > 127 && $dump[$next] < 240) {
        $instruction_text .= "IND " . sprintf("%0.2d", $dump[$next] - 128);
      }

      if ($dump[$next] > 239) {
        given ($dump[$next]) {
          when (240) {  $instruction_text .= "IND T"; }
          when (241) {  $instruction_text .= "IND Z"; }
          when (242) {  $instruction_text .= "IND Y"; }
          when (243) {  $instruction_text .= "IND X"; }
          when (244) {  $instruction_text .= "IND L"; }
          when (245) {  $instruction_text .= "IND M"; }
          when (246) {  $instruction_text .= "IND N"; }
          when (247) {  $instruction_text .= "IND O"; }
          when (248) {  $instruction_text .= "IND P"; }
          when (249) {  $instruction_text .= "IND Q"; }
          when (250) {  $instruction_text .= "IND ⊢"; }
          when (251) {  $instruction_text .= "IND a"; }
          when (252) {  $instruction_text .= "IND b"; }
          when (253) {  $instruction_text .= "IND c"; }
          when (254) {  $instruction_text .= "IND d"; }
          when (255) {  $instruction_text .= "IND e"; }
        }
      }

      $location = $next2;
    }

    # 0x9B-0x9C - ASTO/ARCL - Two byte
    when ($_ > 0x99 && $_ < 0x9C) {

      $instruction_hex =  sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);

      given ($dump[$location]) {
	     when (0x9A) { $instruction_text = "ASTO "; }
        when (0x9B) { $instruction_text = "ARCL "; }
      }

      if ($dump[$next] < 112) {
        $instruction_text .= sprintf("%0.2d", $dump[$next]);
      }

      if ($dump[$next] > 111 && $dump[$next] < 128) {
        given ($dump[$next]) {
          when (112) { $instruction_text .= "T"; }
          when (113) { $instruction_text .= "Z"; }
          when (114) { $instruction_text .= "Y"; }
          when (115) { $instruction_text .= "X"; }
          when (116) { $instruction_text .= "L"; }
          when (117) { $instruction_text .= "M"; }
          when (118) { $instruction_text .= "N"; }
          when (119) { $instruction_text .= "O"; }
          when (120) { $instruction_text .= "P"; }
          when (121) { $instruction_text .= "Q"; }
          when (122) { $instruction_text .= "⊢"; }
          when (123) { $instruction_text .= "a"; }
          when (124) { $instruction_text .= "b"; }
          when (125) { $instruction_text .= "c"; }
          when (126) { $instruction_text .= "d"; }
          when (127) { $instruction_text .= "e"; }
          default { $instruction_text = "INVALID"; }
        }
      }

      if ($dump[$next] > 127 && $dump[$next] < 240) {
        $instruction_text .= "IND " . sprintf("%0.2d", $dump[$next] - 128);
      }

      if ($dump[$next] > 239) {
        given ($dump[$next]) {
          when (240) {  $instruction_text .= "IND T"; }
          when (241) {  $instruction_text .= "IND Z"; }
          when (242) {  $instruction_text .= "IND Y"; }
          when (243) {  $instruction_text .= "IND X"; }
          when (244) {  $instruction_text .= "IND L"; }
          when (245) {  $instruction_text .= "IND M"; }
          when (246) {  $instruction_text .= "IND N"; }
          when (247) {  $instruction_text .= "IND O"; }
          when (248) {  $instruction_text .= "IND P"; }
          when (249) {  $instruction_text .= "IND Q"; }
          when (250) {  $instruction_text .= "IND ⊢"; }
          when (251) {  $instruction_text .= "IND a"; }
          when (252) {  $instruction_text .= "IND b"; }
          when (253) {  $instruction_text .= "IND c"; }
          when (254) {  $instruction_text .= "IND d"; }
          when (255) {  $instruction_text .= "IND e"; }
        }
      }

      $location = $next2;
    }

    # 0x9C-0x9F - FIX, SCI, ENG, TONE - Two bytes
    when ($_ > 0x9B && $_ < 0xA0) {
      $instruction_hex = sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);

      given ($dump[$location]) {
        when (0x9C) { $instruction_text = "FIX "; }
        when (0x9D) { $instruction_text = "SCI "; }
        when (0x9E) { $instruction_text = "ENG "; }
        when (0x9F) { $instruction_text = "TONE "; }
      }

      $instruction_text .= sprintf("%d", $dump[$next]);
      $location = $next2;
    }

    # 0xA0-0xA7 - XROM - Two bytes
    when ($_ > 159 && $_ < 168)
    {
      $instruction_hex = sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);

      # XROM i,j == 160 + i/4, 64(i % 4) + j
      # Thank you, Leo.
      my $i = (($dump[$location] - 160) << 2) + (($dump[$next] >> 6));
      my $j = $dump[$next] & 63;

      $instruction_text = xrom_translate($i,$j);

      $location = $next2;
    }

    # 0xA8-0xAD - SF, CF, FS?C, FC?C, FS?, FC? - Two bytes
    when ($_ > 167 && $_ < 174) {
      $instruction_hex = sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);

      given ($dump[$location]) {
        when (0xA8) { $instruction_text = "SF "; }
        when (0xA9) { $instruction_text = "CF "; }
        when (0xAA) { $instruction_text = "FS?C "; }
        when (0xAB) { $instruction_text = "FC?C "; }
        when (0xAC) { $instruction_text = "FS? "; }
        when (0xAD) { $instruction_text = "FC? "; }
      }

      if ($dump[$next] < 128) {
        $instruction_text .= sprintf("%0.2d", $dump[$next]);
      }

      if ($dump[$next] > 127 && $dump[$next] < 240) {
        $instruction_text .= "IND " . sprintf("%0.2d", $dump[$next] - 128);
      }

      if ($dump[$next] > 239) {
        given ($dump[$next]) {
          when (240) {  $instruction_text .= "IND T"; }
          when (241) {  $instruction_text .= "IND Z"; }
          when (242) {  $instruction_text .= "IND Y"; }
          when (243) {  $instruction_text .= "IND X"; }
          when (244) {  $instruction_text .= "IND L"; }
          when (245) {  $instruction_text .= "IND M"; }
          when (246) {  $instruction_text .= "IND N"; }
          when (247) {  $instruction_text .= "IND O"; }
          when (248) {  $instruction_text .= "IND P"; }
          when (249) {  $instruction_text .= "IND Q"; }
          when (250) {  $instruction_text .= "IND ⊢"; }
          when (251) {  $instruction_text .= "IND a"; }
          when (252) {  $instruction_text .= "IND b"; }
          when (253) {  $instruction_text .= "IND c"; }
          when (254) {  $instruction_text .= "IND d"; }
          when (255) {  $instruction_text .= "IND e"; }
        }
      }

      $location = $next2;
    }

    # 0xAE - GTO IND/XEQ IND
    when (0xAE) {
      $instruction_hex = sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);

      if ($dump[$next] < 128) {
        $instruction_text = "GTO ";
      } else {
        $instruction_text = "XEQ ";
      }
      if ($dump[$next] < 112) {
        $instruction_text .= sprintf("%0.2d", $dump[$next]);
      }

      if ($dump[$next] > 111 && $dump[$next] < 128) {
        given ($dump[$next]) {
          when (112) { $instruction_text .= "IND T"; }
          when (113) { $instruction_text .= "IND Z"; }
          when (114) { $instruction_text .= "IND Y"; }
          when (115) { $instruction_text .= "IND X"; }
          when (116) { $instruction_text .= "IND L"; }
          when (117) { $instruction_text .= "IND M"; }
          when (118) { $instruction_text .= "IND N"; }
          when (119) { $instruction_text .= "IND O"; }
          when (120) { $instruction_text .= "IND P"; }
          when (121) { $instruction_text .= "IND Q"; }
          when (122) { $instruction_text .= "IND ⊢"; }
          when (123) { $instruction_text .= "IND a"; }
          when (124) { $instruction_text .= "IND b"; }
          when (125) { $instruction_text .= "IND c"; }
          when (126) { $instruction_text .= "IND d"; }
          when (127) { $instruction_text .= "IND e"; }
          default { $instruction_text = "INVALID"; }
        }
      }

      if ($dump[$next] > 127 && $dump[$next] < 240) {
        $instruction_text .= "IND " . sprintf("%0.2d", $dump[$next] - 128);
      }

      if ($dump[$next] > 239) {
        given ($dump[$next]) {
          when (240) {  $instruction_text .= "IND T"; }
          when (241) {  $instruction_text .= "IND Z"; }
          when (242) {  $instruction_text .= "IND Y"; }
          when (243) {  $instruction_text .= "IND X"; }
          when (244) {  $instruction_text .= "IND L"; }
          when (245) {  $instruction_text .= "IND M"; }
          when (246) {  $instruction_text .= "IND N"; }
          when (247) {  $instruction_text .= "IND O"; }
          when (248) {  $instruction_text .= "IND P"; }
          when (249) {  $instruction_text .= "IND Q"; }
          when (250) {  $instruction_text .= "IND ⊢"; }
          when (251) {  $instruction_text .= "IND a"; }
          when (252) {  $instruction_text .= "IND b"; }
          when (253) {  $instruction_text .= "IND c"; }
          when (254) {  $instruction_text .= "IND d"; }
          when (255) {  $instruction_text .= "IND e"; }
        }
      }

      $location = $next2;
    }

    # 0xAF - SPARE  (wut)
    when (0xAF) {
      $instruction_hex = sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);
      $instruction_text = "SPARE";
      $location = $next2;
    }

    # 0xB0-0xBF - SPARE and GTO - Two Bytes
    when ($_ >> 4 == 11) {

      my $LSN = $_ & 15;
      $instruction_hex = sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]) ;

      if ($LSN == 0) {
        $instruction_text = "SPARE " . sprintf("%0.2d", $dump[$next]);
      } else {
        $instruction_text = "GTO " . sprintf("%0.2d", $dump[$location] - 177);
      }

      $location = $next2;

    }

    # 0xC0-0xCD - GLOBALs - LBL " and END - Many bytes.
    when ($_ >> 4 == 12 && $_ < 206) {

      my $label;
      my $labelhex = sprintf("%0.2x%0.2x%0.2x", $dump[$location], $dump[$next], $dump[$next2]);
      my $labelbytes = nextbyte $next2;

      # Is it a label?
      if ($dump[$next2] >= 240) {

        # Pull out and display the key assignment and LBL instruction's text.
        for (my $i = 0; $i < $dump[$next2] - 240; $i++) {

          # Key assignment, if applicable.
          if ($i == 0) {
            $labelhex = $labelhex . sprintf("%0.2x", $dump[$labelbytes]);
            $labelbytes = nextbyte $labelbytes;
            next
          };

          $label = $label . alphatranslate(chr $dump[$labelbytes]);
          $labelhex = $labelhex . sprintf("%0.2x", $dump[$labelbytes]);
          $labelbytes = nextbyte $labelbytes;
        }

        $instruction_hex = $labelhex;
        $instruction_text = "LBL \"" . $label . "\"";
        $location = $labelbytes;

      # If it's not a label, it's an END.
      } else {

        $instruction_hex = sprintf("%0.2x%0.2x%0.2x", $dump[$location], $dump[$next], $dump[$next2]) ;
        $instruction_text = "END";
        $location = nextbyte $next2;

      }

    }

    # 0xCE - X<>__ - Two bytes
    when (0xCE) {
      $instruction_hex = sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);
      $instruction_hex =  sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);

      $instruction_text = "X<> ";

      if ($dump[$next] < 112) {
        $instruction_text .= sprintf("%0.2d", $dump[$next]);
      }

      if ($dump[$next] > 111 && $dump[$next] < 128) {
        given ($dump[$next]) {
          when (112) { $instruction_text .= "T"; }
          when (113) { $instruction_text .= "Z"; }
          when (114) { $instruction_text .= "Y"; }
          when (115) { $instruction_text .= "X"; }
          when (116) { $instruction_text .= "L"; }
          when (117) { $instruction_text .= "M"; }
          when (118) { $instruction_text .= "N"; }
          when (119) { $instruction_text .= "O"; }
          when (120) { $instruction_text .= "P"; }
          when (121) { $instruction_text .= "Q"; }
          when (122) { $instruction_text .= "⥼"; }
          when (123) { $instruction_text .= "a"; }
          when (124) { $instruction_text .= "b"; }
          when (125) { $instruction_text .= "c"; }
          when (126) { $instruction_text .= "d"; }
          when (127) { $instruction_text .= "e"; }
          default { $instruction_text = "INVALID"; }
        }
      }

      if ($dump[$next] > 127 && $dump[$next] < 240) {
        $instruction_text .= "IND " . sprintf("%0.2d", $dump[$next] - 128);
      }

      if ($dump[$next] > 239) {
        given ($dump[$next]) {
          when (240) {  $instruction_text .= "IND T"; }
          when (241) {  $instruction_text .= "IND Z"; }
          when (242) {  $instruction_text .= "IND Y"; }
          when (243) {  $instruction_text .= "IND X"; }
          when (244) {  $instruction_text .= "IND L"; }
          when (245) {  $instruction_text .= "IND M"; }
          when (246) {  $instruction_text .= "IND N"; }
          when (247) {  $instruction_text .= "IND O"; }
          when (248) {  $instruction_text .= "IND P"; }
          when (249) {  $instruction_text .= "IND Q"; }
          when (250) {  $instruction_text .= "IND ⊢"; }
          when (251) {  $instruction_text .= "IND a"; }
          when (252) {  $instruction_text .= "IND b"; }
          when (253) {  $instruction_text .= "IND c"; }
          when (254) {  $instruction_text .= "IND d"; }
          when (255) {  $instruction_text .= "IND e"; }
        }
      }

      $location = $next2;
    }

    # 0xCF - LBL __ - Two bytes
    when (0xCF) {
      $instruction_hex = sprintf("%0.2x%0.2x", $dump[$location], $dump[$next]);

      my $labeladdr;
      my $labelraw = $dump[$next];

      if ($labelraw > 101 && $labelraw < 112) {
        $labeladdr = chr ($labelraw - 37)
      } else {
        given ($labelraw) {
          when (112) { $labeladdr = "T"; }
          when (113) { $labeladdr = "Z"; }
          when (114) { $labeladdr = "Y"; }
          when (115) { $labeladdr = "X"; }
          when (116) { $labeladdr = "L"; }
          when (117) { $labeladdr = "M"; }
          when (118) { $labeladdr = "N"; }
          when (119) { $labeladdr = "O"; }
          when (120) { $labeladdr = "P"; }
          when (121) { $labeladdr = "Q"; }
          when (122) { $labeladdr = "⊢"; }
          when (123) { $labeladdr = "a"; }
          when (124) { $labeladdr = "b"; }
          when (125) { $labeladdr = "c"; }
          when (126) { $labeladdr = "d"; }
          when (127) { $labeladdr = "e"; }
          default { $labeladdr = "INVALID " . $labelraw; }
        }
      }

      $instruction_text = "LBL $labeladdr";
      $location = $next2;

    }

    # 0xD0-0xDF - GTO xx - Three bytes
    when ($_ >> 4 == 13) {

      $instruction_hex = sprintf("%0.2x%0.2x%0.2x", $dump[$location], $dump[$next], $dump[$next2]) ;

      $instruction_text = "GTO "; # . sprintf("%d", $dump[$next2]);

      if ($dump[$next2] > 101 && $dump[$next2] < 112) {
        $instruction_text .= chr ($dump[$next2] - 37);
      } else {
        given ($dump[$next2]) {
          when (112) { $instruction_text .= "T"; }
          when (113) { $instruction_text .= "Z"; }
          when (114) { $instruction_text .= "Y"; }
          when (115) { $instruction_text .= "X"; }
          when (116) { $instruction_text .= "L"; }
          when (117) { $instruction_text .= "M"; }
          when (118) { $instruction_text .= "N"; }
          when (119) { $instruction_text .= "O"; }
          when (120) { $instruction_text .= "P"; }
          when (121) { $instruction_text .= "Q"; }
          when (122) { $instruction_text .= "⊢"; }
          when (123) { $instruction_text .= "a"; }
          when (124) { $instruction_text .= "b"; }
          when (125) { $instruction_text .= "c"; }
          when (126) { $instruction_text .= "d"; }
          when (127) { $instruction_text .= "e"; }
          default { $instruction_text .= "INVALID " . $dump[$next2]; }
        }
      }

        $location = nextbyte $next2;

    }

    # 0xE0-0xEF - XEQ xx and XEQ IND xxx - Three bytes
    when ($_ >> 4 == 14) {

        $instruction_hex = sprintf("%0.2x%0.2x%0.2x", $dump[$location], $dump[$next], $dump[$next2]) ;
      $instruction_text = "XEQ ";

      if ($dump[$next2] < 100) { $instruction_text .= sprintf("%0.2d", $dump[$next2]) };

      if ($dump[$next2] > 101 && $dump[$next2] < 112) {
        $instruction_text .= chr ($dump[$next2] - 37);
      }

      if ($dump[$next2] > 111 && $dump[$next2] < 128) {
        given ($dump[$next2]) {
          when (112) { $instruction_text .= "T"; }
          when (113) { $instruction_text .= "Z"; }
          when (114) { $instruction_text .= "Y"; }
          when (115) { $instruction_text .= "X"; }
          when (116) { $instruction_text .= "L"; }
          when (117) { $instruction_text .= "M"; }
          when (118) { $instruction_text .= "N"; }
          when (119) { $instruction_text .= "O"; }
          when (120) { $instruction_text .= "P"; }
          when (121) { $instruction_text .= "Q"; }
          when (122) { $instruction_text .= "⊢"; }
          when (123) { $instruction_text .= "a"; }
          when (124) { $instruction_text .= "b"; }
          when (125) { $instruction_text .= "c"; }
          when (126) { $instruction_text .= "d"; }
          when (127) { $instruction_text .= "e"; }
          default { $instruction_text .= "INVALID " . $dump[$next2]; }
        }
      }

      if ($dump[$next2] > 127 && $dump[$next2] < 240) {
        $instruction_text .= sprintf("%0.2d", $dump[$next2] - 128);
      }

      if ($dump[$next2] > 239) {
        given ($dump[$next2]) {
          when (240) {  $instruction_text .= "IND T"; }
          when (241) {  $instruction_text .= "IND Z"; }
          when (242) {  $instruction_text .= "IND Y"; }
          when (243) {  $instruction_text .= "IND X"; }
          when (244) {  $instruction_text .= "IND L"; }
          when (245) {  $instruction_text .= "IND M"; }
          when (246) {  $instruction_text .= "IND N"; }
          when (247) {  $instruction_text .= "IND O"; }
          when (248) {  $instruction_text .= "IND P"; }
          when (249) {  $instruction_text .= "IND Q"; }
          when (250) {  $instruction_text .= "IND ⊢"; }
          when (251) {  $instruction_text .= "IND a"; }
          when (252) {  $instruction_text .= "IND b"; }
          when (253) {  $instruction_text .= "IND c"; }
          when (254) {  $instruction_text .= "IND d"; }
          when (255) {  $instruction_text .= "IND e"; }
        }
      }

      $location = nextbyte $next2;
    }

    # 0xF0-0xFF - Text fields - Many bytes
    when ($_ >> 4 == 15) {

      my $label;
      my $labelhex = sprintf("%0.2x", $dump[$location]);
      my $labelbytes = nextbyte $location;

      # Pull out and deliver the text field.
      for (my $i = 0; $i < $_ - 240; $i++) {

          # Provides fixes for HP-41C special characters.  Maps to
          # UTF-8 lookalikes.
          $label = $label . alphatranslate(chr $dump[$labelbytes]);
          $labelhex = $labelhex . sprintf("%0.2x", $dump[$labelbytes]);
          $labelbytes = nextbyte $labelbytes;
      }

      # Display APPEND in a more legacy friendly >", 
      # instead of literally "⊢
      if (substr($label, 0, 1) eq "⊢" ) {
        $instruction_text = ">\"" . substr($label, 1, length $label) . "\"";
      } else {
        $instruction_text = "\"" . $label . "\"";
      }
      $instruction_hex = $labelhex;
      $location = $labelbytes;

    }

    default {
      $instruction_hex = sprintf("%0.2x", $dump[$location]);
      $instruction_text = "UNKNOWN BYTE: " . sprintf("%0.2x", $dump[$location]);
      $location = $next;
    }
  }

  return ($location, $instruction_hex, $instruction_text);

}

######
#
# list_program - Decompile memory into a coherent list of instructions to a program.
#
######
sub list_program {

  my ($program_name,
               @dump) = @_;

  # Calculate where the programs lie in the memory space, based on
  # the status register 0x0D.  Byte 95 and the top nybble of 96
  # make up the program space's top.  The bottom nybble of 96 and
  # all of 97 make up the end of the program space.
  my $program_top = ($dump[95] * 16) + ($dump[96] >> 4) - 1;
  my $program_limit = (($dump[96] & 15) * 256) + $dump[97];

  my $program_start = 0;         # We find the real value below.
  my $program_counter = 0;	 # For producing line numbers.
  my $program_pointer = 0;       # For moving through memory.

  my $program_instruction = "";
  my $program_hex = "";

  # Find the register where the desired program starts.  We start at the top
  # and work our way down registerwise, just like the programs do.
  for (my $i = $program_top * 7; $i >= $program_limit * 7; $i = nextbyte $i) {

    my $next			= nextbyte $i;				# For going forward
    my $next2			= nextbyte nextbyte $i;		        # END and LBL are 3 byte

    # For assembling label names.
    my $label = "";
    my $labelhex = "";
    my $labelbytes = nextbyte $next2;

    # Find GLOBAL bytes
    if ($dump[$i] >> 4 == 12 && ($dump[$i] & 15) <= 13) {

      # Is it a label?
      if ($dump[$next2] >= 240) {

        $labelhex = sprintf("%0.2x%0.2x%0.2x", $dump[$i], $dump[$next], $dump[$next2]) ;

        # Pull out and display the key assignment and LBL instruction's text.
        for (my $i = 0; $i < $dump[$next2] - 240; $i++) {

          # Key assignment, if applicable.
          if ($i == 0) {
            $labelbytes = nextbyte $labelbytes;
            $labelhex = $labelhex . "00";
            next
          };

          # Provides fixes for HP-41C special characters.  Maps to
          # UTF-8.
          $label = $label . alphatranslate(chr $dump[$labelbytes]);
          $labelhex = $labelhex . sprintf("%0.2x", $dump[$labelbytes]);
          $labelbytes = nextbyte $labelbytes;

        }

      }

    }

    # Have we found the label we're looking for?
    if ( $label eq $program_name) {
      $program_counter++;
      $program_start = $labelbytes;
      print "Program \"$label\"\n";
      print "---------------------------------------------------\n";
      print sprintf("%0.3d\t%-25s%-25s\n", $program_counter, "LBL \"$label\"", $labelhex);
      $program_hex = $labelhex;
      last;
    }

  }

  # If we didn't find it, the default value will still be present.  This value
  # is invalid in a normally operating machine.
  if ($program_start == 0) {
    print "\nProgram $program_name does not exist.\n\n";
    return 0;
  }

  # Now the fun loop.  Retrieve and display instructions until END
  # is reached.
  $program_pointer = $program_start;

  while ( $program_instruction ne "END" ) {

    my $oldpointer = $program_pointer;
    my $temphex = "";

    $program_counter++;

    ($program_pointer,
     $temphex,
     $program_instruction) = parse_memory($oldpointer, @dump);

      $program_hex = $program_hex . $temphex;

      print sprintf("%0.3d\t%-25s%-25s\n", $program_counter, $program_instruction, $temphex);

  }

  print "\n---------------------------------------------------\n";
  print "\n$program_hex\n";
  print "\n---------------------------------------------------\n";
  print "Size: " . (length $program_hex) / 2 . " bytes\n\n";
}

######
#
# inject_code - Insert hexadecimal-coded binary string into program memory.
#               This preserves the last .END. and moves it down in program space.
#
######
sub inject_code {

  my ($injection,
           @dump) = @_;

  my $limit_register = "";

  # Calculate where the programs lie in the memory space, based on
  # the status register 0x0D.  Byte 95 and the top nybble of 96
  # make up the program space's top.  The bottom nybble of 96 and
  # all of 97 make up the end of the program space.
  my $program_top = ($dump[95] * 16) + ($dump[96] >> 4) - 1;
  my $program_limit = (($dump[96] & 15) * 256) + $dump[97];

  # Calculate the number of main RAM registers remaining, by searching for
  # the last register beginning with F0, between the bottom of RAM and the
  # bottom .END..  This indicates the last alarm or key assignment register.
  my $program_bottom = $program_limit ;

  for (my $i = $program_limit - 1; $i >= 192; $i--) {

    # Hex value 0xF0 marks the bottom of the space we can use
    # to add programs.  This marker actually moves around!
    if ( $dump[$i * 7] == 240 ) {
      last;
    }

    $program_bottom--;

  }

  my $inject_size = (length($injection) / 2) / 7;

  # Round up for accounting purposes.  We're deliberately padding the program
  # to ensure there's always at least one, maybe two, program registers left
  # over, just in case...
  if ((length($injection) % 7) > 0) { $inject_size = int $inject_size + 1; }

  #$inject_size++;

  print "DEBUG: Code to be injected: \"$injection\"\n";
  print "DEBUG: " . length($injection) / 2 . " bytes.\n";
  print "DEBUG: Injected code size is " . ($inject_size) . " registers.\n";
  print "DEBUG: We have " . ($program_limit - $program_bottom) . " registers of free memory available.\n";

  # Preflight: Do we have enough room?
  if ($inject_size > ($program_limit - $program_bottom)) {
    die "FATAL: Injected code is larger than space remaining in main memory.\n";
  }

  my $pointer = $program_limit * 7;

  # Preflight: Save the last END
  for (my $i = 0;$i < 7; $i++) {
    $limit_register .= sprintf("%0.2x", $dump[($program_limit * 7) + $i]);
  }

  printf "DEBUG: .END. register contents were: $limit_register\n";

  printf "DEBUG: Injecting " . (length($injection)/2) . " bytes into memory.\n";
  for (my $i = 0; $i < length($injection); $i = $i + 2) {
    $dump[$pointer] = hex substr($injection, $i, 2);
#    print "DEBUG: $i: Injecting " . substr($injection, $i, 2) . " at $pointer.\n";
    $pointer = nextbyte $pointer;
  }


$pointer = ((int ($pointer / 7) - 1) * 7) + 4;

$dump[$pointer] = 0xC4;
$pointer = nextbyte $pointer;
$dump[$pointer] = 0x01;
$pointer = nextbyte $pointer;
$dump[$pointer] = 0x29;
$pointer = nextbyte $pointer;


$program_limit = sprintf("%0.3x", ($pointer) / 7 + 1);
print "DEBUG: New program limit is at 0x$program_limit.\n";

  $dump[96] = ($dump[96] & 240) + hex (substr($program_limit, 0, 1));
  $dump[97] = hex (substr($program_limit, 1, 2));


  # Recalculate memory space available.
  $program_limit = (($dump[96] & 15) * 256) + $dump[97];
  $program_bottom = $program_limit ;
  for (my $i = $program_limit - 1; $i >= 192; $i--) {
    if ( $dump[$i * 7] == 240 ) {
      last;
    }
    $program_bottom--;
  }

  print "DEBUG: We have " . ($program_limit - $program_bottom) . " registers of free memory available.\n";

  return (@dump);
}
#=====================================
# Main Execution Happens Here.
#=====================================

# Display helpful message if needed.
if ($help) { printUsage(); }

# If we have an outside filename to use, use it.  Otherwise,
# spit out a warning
if ($fname) {

  # Pull all of the required data from the memory dump file.
  (
    $cpuregisters[0],		# A
    $cpuregisters[1],		# B
    $cpuregisters[2],		# C
    $cpuregisters[3],		# M
    $cpuregisters[4],		# N
    $cpuregisters[5],		# G
    @memory,
  ) = loadfile($fname);

}  else {

print "\nWARNING: No filename given to analyze.  This script initializes a \n";
print "         blank memory map to work with in the absence of outside\n";
print "         data.  This is probably not what you want.  See '--help'\n";
print "         for a list of options that will include importing exist-\n";
print "         ing data.\n\n";

}

if ($print) { printfile(@cpuregisters, @memory); }
if ($inject) {
  @memory = inject_code($inject, @memory);
  printfile(@cpuregisters, @memory);
 # dump_summary(@memory);
}
if ($summary) { dump_summary(@memory) };
if ($list) {
  my $pname = decode("utf-8", $list);
  list_program(uc $pname, @memory)
}
