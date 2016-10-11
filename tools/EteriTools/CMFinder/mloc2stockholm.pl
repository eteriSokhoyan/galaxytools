#!/usr/bin/perl -w
use warnings;
use strict;
use POSIX;
use Getopt::Long;

my $usage = << "JUS";
  USAGE:  ./mloc2stockhol.pl -file STRING
  OPTIONS:
    -file		[MANDATORY]	File to convert into stockholm format

    -split_input	[OPTIONAL][yes||no]	REGULATES THE PROCESSING OF THE INPUT:   DEFAULT IS "no"

						IF "yes": the stockholm format is generated out of two files:
						  a) clustalw multiple alignment file, generated by locarna-program, and
						  b) consensus structure information file
						IF "no": the clustalw multiple alignment file contains both, the multiple alignment AND the consensus
						structure information. This single file is sufficient to generate the stockholm format file.
    -con_struct		[OPTIONAL]	File containing the consensus structure information in the second line. Must be inputed, if split_input is "yes"

    -interval_only	[OPTIONAL][yes||no]	REGULATES THE USAGE OF A locaRNAP RESULT INTERVAL. STANDARD IS "NO", IF "YES" IS CHOOSEN,
						a corresponding rel_signal-file has to be present for the cleavage adresses.
    -rel_signal		[OPTIONAL]	Has to be provided, if interval_only is set to "yes". Contains the interval for the cleavage process.

    -mode		[OPTIONAL][SE|RSE|NO]	Has to be set, if a relative signal has been provided
						SE: SIMPLE EXTENTION MODEL
						RSE: RELATIVE EXTENTION/PRUNING MODEL
						NO: THERE AIN'T NO MODIFICATIONS
    -h 			[OPTIONAL]	Prints help text

JUS

my $file;
my $con_struct;
my $split_input = "no";
my $rel_signal;
my $mode          = "SE";
my $interval_only = "no";
my $opt_h         = 0;
usage()

  unless GetOptions(
  "h"               => \$opt_h,
  "con_struct:s"    => \$con_struct,
  "split_input:s"   => \$split_input,
  "rel_signal:s"    => \$rel_signal,
  "interval_only:s" => \$interval_only,
  "mode:s"          => \$mode,
  "file=s"          => \$file
  );
my $rel_s = 0;

if ($opt_h) {
  print STDERR $usage;
  exit;
}

#######################
### CHECKLIST
#######################
if ( !$file ) {
  print "No file to convert....\n";
  print STDERR $usage;
  exit;
}
if ( $split_input eq "yes" ) {
  if ( !$con_struct ) {
    print "consensus structure information is missing, since split_input is set to " . "yes" . " !\n";
    print STDERR $usage;
    exit;
  }
}
if ( $interval_only eq "yes" ) {
  if ( !$rel_signal or !$mode ) {
    print "$rel_signal rel_signal information or mode information is missing, since interval_only is set to " . "yes" . " !\n";
    print STDERR $usage;
    exit;
  } elsif ($rel_signal) {
    $rel_s = 1;
  }

}


#####################################################################
### READ-OUT OF INPUT FILES AND CREATION OF "STOCKHOLM"-FILE
#####################################################################

my $structure = "";
my $scount    = 0;
my %elements;
my @heads;
my @bodies;
my $blank     = 0;
my $blankline = "#=GC SS_cons";
my $clline    = "#=GC RF";
my $header;
my $newblock = 1;

open CLUSTAL, "<$file" or die "Can not open specified file!";

if ( $split_input eq "no" ) {

  while (<CLUSTAL>) {
    if (/CLUSTAL\.*/) {
      chomp;
    }

    elsif ( /(\s){10,}(\(|\)|\-|\.)/ and $newblock == 1 ) {
      chomp;
      while ( substr( $_, 0, 1 ) eq " " ) {
        substr( $_, 0, 1, "" );
      }
      $_ =~ s/\(/</g;
      $_ =~ s/\)/>/g;
      $_ =~ s/-/./g;
      $structure .= $_;
      if ( $scount == 0 ) {
        $scount = 1;
      }
      $newblock = 0;
    }

    elsif ( /(\s){10,}(\(|\)|\-|\.)/ and $newblock == 0 ) {
      if ( $scount == 1 ) {
        $scount = 2;
      }
    } elsif ( (/\w*\W*\w*/) and $scount == 1 ) {
      chomp;
      my @line = split;
      if ( !exists $elements{ $line[0] } ) {
        $elements{ $line[0] } = $line[1];
      } else {
        my $tmp_val = $elements{ $line[0] };
        $tmp_val .= $line[1];
        delete( $elements{ $line[0] } );
        $elements{ $line[0] } = $tmp_val;
      }
      if ( length( $line[0] ) + 3 > length($blankline) ) {
        $blank = length( $line[0] ) + 3;
      }
    } else {
      $newblock = 1;
      $scount   = 0;
    }
  }
} elsif ( $split_input eq "yes" ) {

  open CON_STRUCT, "<$con_struct" or die "Could not open structure-file!";
  my $line_counter = 1;
  while (<CON_STRUCT>) {

    if ( $line_counter == 2 ) {
      chomp;
      $_ =~ s/\(/</g;
      $_ =~ s/\)/>/g;
      $_ =~ s/-/./g;
      $structure = $_;
      $structure =~ s/\s+.*$//g;

      #       print $structure."\n";
    }
    $line_counter = $line_counter + 1;
  }

  while (<CLUSTAL>) {
    if (/CLUSTAL\.*/) { }
    elsif ( (/([\w]+[\W]+[\w\-\~]+)$/) ) {
      chomp;
      my @line = split;
      $line[1] =~ s/~/-/g;
      if ( !exists $elements{ $line[0] } ) {
        $elements{ $line[0] } = $line[1];
      } else {
        my $tmp_val = $elements{ $line[0] };
        $tmp_val .= $line[1];
        delete( $elements{ $line[0] } );
        $elements{ $line[0] } = $tmp_val;
      }
    } else {
    }
  }

  close(CON_STRUCT);
}
close(CLUSTAL);

my $max_head_len = 0;
foreach my $key ( keys %elements ) {

  #    print "$key \t $elements{$key}\n";
  push( @heads,  $key );
  push( @bodies, $elements{$key} );

  $max_head_len = length($key) if ( length($key) > $max_head_len );
}

$max_head_len = length($blankline) if ( length($blankline) > $max_head_len );
$max_head_len += 10;
###################################################################################################################
### PARSING THE RELATIVE SEGMENTS OF THE ALIGNMENT AND PROCESSING (EXTENDING/PRUNING) THE ALIGNMENTBLOCK
###################################################################################################################
if ( $rel_s == 1 ) {
  my $interval_start;
  my $interval_stop;
  my $feed;
  open REL, "< $rel_signal" or die "rel_signal file could not be opened!";
  while (<REL>) {
    if (/FIT/) {
      chomp;
      my @fit_line = split;
      $interval_start = $fit_line[1] - 1;
      $interval_stop  = $fit_line[2] - 1;

      #     print $interval_start."\n";
      #     print $interval_stop."\n";
      $feed = $interval_stop - $interval_start + 1;
    }
  }
  close(REL);
  my @temp_var;
  for ( my $i = 0 ; $i < scalar(@bodies) ; $i++ ) {
    $temp_var[$i] = substr( $bodies[$i], $interval_start, $feed );
  }

##################################################
### CONSISTENCE CHECK OF THE STRUCTURE
##################################################
  my $substructure = substr( $structure, $interval_start, $feed );
  my $consistence  = 0;
  my $seq_fraction = length($substructure) / length($structure);
  while ( $consistence == 0 ) {
### BUILDING UP THE STRUCTURE STACK
    my $bracket = 0;
    my $stack   = "";
    my @stackinfo;
    my @stackstruct;
    for ( my $i = 0 ; $i < length($substructure) ; $i++ ) {
      my $pos = substr( $substructure, $i, 1 );
      if ( $pos eq "<" ) {
        $stack .= "<";
        push( @stackinfo, $i );
        $bracket += 1;
      } elsif ( $pos eq ">" ) {
        $stack .= ">";
        push( @stackinfo, $i );
        $bracket -= 1;
      }

    }

    # print $stack."\n";
    for ( my $i = 0 ; $i < length($substructure) ; $i++ ) {
      $stackstruct[$i] = "_";
    }

    #     print scalar(@stackstruct)."\n";
    #     print $substructure."\n";
    #       for(my $i = 0; $i < scalar(@stackstruct); $i ++){
    # 	 print $stackstruct[$i];
    #       }
    #     print "\n";
### REMOVING PAIRING BASES OUT OF THE STACK
    my $pairs         = 1;
    my $istart        = 0;
    my $istop         = 0;
    my $subID         = 0;
    my @lowerIDborder = (0);
    my @upperIDborder = (0);
    while ( $pairs == 1 ) {
      $pairs = 0;

      for ( my $i = 0 ; $i < length($stack) - 1 ; $i++ ) {

        if ( substr( $stack, $i, 1 ) eq "<" and substr( $stack, $i + 1, 1 ) eq ">" ) {
          substr( $stack, $i, 2, "" );
          $pairs = 1;
        }
      }
    }


### CHECK OF CONSISTENCE | OTHER MODEL WILL BE ADDED
    $mode = uc($mode);
### SIMPLE EXTENTION MODEL: IF REDUCED STACK STRUCTURE IS INCOMPLETE, THE STRUCTURE WILL BE EXTENDED INTO THE
### INCOMPLETE DIRECTION AND WILL BE RE-EVALUATED ITERATIVELY

    if ( $mode eq "NO" ) {

      $consistence = 1;
    } elsif ( $mode eq "SE" ) {

      if ( $stack eq "" ) {
        $consistence = 1;
      } elsif ( substr( $stack, 0, 1 ) eq ">" ) {
        $interval_start -= 1;
        $feed += 1;
        $substructure = substr( $structure, $interval_start, $feed );
        for ( my $i = 0 ; $i < scalar(@bodies) ; $i++ ) {
          $temp_var[$i] = substr( $bodies[$i], $interval_start, $feed );
        }
      } elsif ( substr( $stack, length($stack) - 1, 1 ) eq "<" ) {
        $feed += 1;
        $substructure = substr( $structure, $interval_start, $feed );
        for ( my $i = 0 ; $i < scalar(@bodies) ; $i++ ) {
          $temp_var[$i] = substr( $bodies[$i], $interval_start, $feed );
        }
      }

       #print $stack."\n";
    }
### RELATIVE SIZE OF THE ALIFOLD-FRAGMENT - DEPENDENT EXTENTION MODEL "50/50"

  }

### REWRITING OF THE SEQUENCES AND THE STRUCTURE
  for ( my $m = 0 ; $m < scalar(@temp_var) ; $m++ ) {
    $bodies[$m] = $temp_var[$m];
  }
  $structure = $substructure;
}

while ( length($blankline) < $blank ) {
  $blankline .= " ";
}

### PARTITIONING OF SEQUENCE AND STRUCTURE LINE INTO "READABLE" FRAGMENTS -> PRINTING THE "STOCKHOLM" FILE

my $stockholm = $file . ".sth";
open STOCKHOLM, ">$stockholm" or die "Error in opening stockholm file!";
print STOCKHOLM "# STOCKHOLM 1.0\n\n";

for ( my $k = 0 ; $k < scalar(@heads) ; $k++ ) {

  my $b = "";
  for ( my $h = length( $heads[$k] ) ; $h < $max_head_len ; $h++ ) {
    $b .= " ";
  }

  print STOCKHOLM $heads[$k] . $b . $bodies[$k] . "\n";
}

$b = "";
for ( my $h = length($blankline) ; $h < $max_head_len ; $h++ ) {
  $b .= " ";
}
print STOCKHOLM $blankline . $b . $structure . "\n";

print STOCKHOLM "//";
close STOCKHOLM;
