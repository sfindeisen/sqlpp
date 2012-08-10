#!/usr/bin/perl
#
# A very simple PL/SQL preprocessor.
#
# Copyright (C) 2009, 2010 Stanislaw Findeisen <stf at eisenbits.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Changes history:
#
# 2009-07-30 (STF) Initial version.
# 2009-08-05 (STF) Version date.
# 2009-09-04 (STF) Support for UTF-8 output.

use warnings;
use strict;
use utf8;
use integer;

use constant {
    KEY_FILE          => 1,
    KEY_LINE          => 2,
    KEY_SYMBOL        => 3,
    KEY_SYMBOL_VALUE  => 4,
    KEY_LINE_CONTENTS => 5,

    RE_INCLUDE => qr/^#include(\s+)([-0-9a-zA-Z_\.\/]+)(\s*)$/,
    RE_DEFINE  => qr/^#define(\s+)([-0-9a-zA-Z_\.]+)(\s+)([\S ]*?)(\s*)$/,
    RE_SYMBOL  => qr/([-0-9a-zA-Z_\.]+)/,

    # wlasciwe pliki: komentarz
    RE_COMMENT => qr/^\s*#.*$/,

    VERSION      => '1.1',
    VERSION_DATE => '2009-09-04'
};

use Cwd qw(cwd realpath);
use File::Spec::Functions qw(file_name_is_absolute rel2abs);
use File::Basename;

my %parsedFiles     = ();
my %declaredSymbols = ();
my $verbose         = 0;

sub printPrefix {
    # my $prefix = shift;
    # unshift(@_, $prefix);
    # my $msg = join('', @_);
    # chomp($msg);
    # local $| = 1;
    # print(STDERR "$msg\n");

    my $prefix  = shift;
    my $msg     = join('', @_);
    chomp($msg);
    my @msgList = split(/\n/, $msg);

    local $| = 1;
    foreach (@msgList) {
        print(STDERR "$prefix$_\n");
    }
}

sub debug {
    printPrefix('[debug] ', @_) if ($verbose);
}

sub warning {
    printPrefix('[warn]  ', @_);
}

sub error {
    printPrefix('[error] ', @_);
}

sub info {
    printPrefix('[info]  ', @_);
}

sub fatal {
    error(@_);
    die(@_);
}

# TODO This does not take into account things like multiline comments or
# multiline strings.
sub getTransformedLine {
    my $ttm = shift;    # line / text to match
    my $ltr = '';       # transformed line

    if ($ttm =~ RE_COMMENT) {
        # this is a comment line - no substitutions
        return $ttm;
    }

    while ($ttm =~ RE_SYMBOL) {
        my $smb  = $1;
           $ltr .= $`;   # text before the match
        if (my $decl = $declaredSymbols{$smb}) {
            my $sval = ${$decl}{KEY_SYMBOL_VALUE()};
               $ltr .= $sval;
        } else {
            $ltr .= $&;  # matched text
        }
        $ttm = $';       # text after the match
    }

    $ltr .= $ttm;        # remaining line suffix (no symbol matches there)
    return $ltr;
}

sub onRedefinition {
    my $file   = shift;
    my $lineNo = shift;
    my $line   = shift;
    my $decl   = shift;

    my $declFile         = ${$decl}{KEY_FILE()};
    my $declSymb         = ${$decl}{KEY_SYMBOL()};
    my $declLine         = ${$decl}{KEY_LINE()};
    my $declLineContents = ${$decl}{KEY_LINE_CONTENTS()};

    chomp($declLineContents);
    chomp($line);

    my $flInfo   = ((defined($file) ? "$file:" : 'input line ') . $lineNo);
       $declFile = '<STDIN>' unless (defined($declFile));
    warning("$flInfo: $declSymb already defined!\n  $line\nFirst defined here: $declFile:$declLine\n  $declLineContents\nWe use the first definition...");
}

# Parses given file.
#
# Parameters:
#   file path     - if undef, STDIN will be used
#   fixMe         - 0 iff parse only, 1 if produce output
# Returns:
#   transformed file contents (if fixMe was specified)
sub parseFile {
    my $filePath    = shift;
    my $fixMe       = shift;
    my $fileDir     = undef;
    my $fh          = undef;
    my @outputLines = ();

    if (defined($filePath)) {
        $filePath = realpath($filePath);

        if ($parsedFiles{$filePath}) {
            warning("   loop: $filePath");
            return;
        }

        info("Parsing: $filePath");
        $parsedFiles{$filePath} = 1;

        $fileDir = dirname($filePath);
        open($fh, '<:utf8', $filePath) or fatal('Cannot read file! ' . $filePath);
    } else {
        info("Parsing  STDIN");
        $fileDir = cwd();
        open($fh, '<&STDIN') or fatal('Cannot dup STDIN!');
    }

    while (defined(my $line = <$fh>)) {
        my $ln = sprintf("% 5lu", $.);   # line number

        if ($line =~ RE_INCLUDE) {
            my $incFileName = $2;
            debug("  $ln: #include $incFileName#");
            # push(@outputLines, $line) if ($fixMe);
            $incFileName = ($fileDir . '/' . $incFileName) unless file_name_is_absolute($incFileName);
            parseFile($incFileName, 0);
        } elsif ($line =~ RE_DEFINE) {
            my ($defSymbol, $defValue) = ($2, $4);
            debug("  $ln: #define $defSymbol $defValue#");
            # push(@outputLines, $line) if ($fixMe);

            if (my $decl = $declaredSymbols{$defSymbol}) {
                onRedefinition($filePath, $., $line, $decl);
            } else {
                my %decl = (
                    KEY_FILE()          => $filePath,
                    KEY_SYMBOL()        => $defSymbol,
                    KEY_SYMBOL_VALUE()  => $defValue,
                    KEY_LINE()          => $.,
                    KEY_LINE_CONTENTS() => $line
                );
                $declaredSymbols{$defSymbol} = \%decl;
            }
        } elsif ($fixMe) {
            push(@outputLines, getTransformedLine($line));
        }
    }

    close($fh);
    debug("-------  $filePath DONE") if (defined($filePath));
    return @outputLines;
}

sub printHelp {
    my $sqlppver     = VERSION();
    my $sqlppverdate = VERSION_DATE();
    print <<"ENDHELP";
sqlpp $sqlppver ($sqlppverdate)

Copyright (C) 2009, 2010 Stanislaw Findeisen <stf at eisenbits.com>
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/>
This is free software: you are free to change and redistribute it.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

A very simple PL/SQL preprocessor. Use #includes and #defines in
your PL/SQL code (like in C) and then run sqlpp to replace constant
names with their values.

Usage:
  $0 [--verbose] [-i file] [-o file]

If no input (output) file is specified then standard input (output) is
read (written).

BUGS/FEATURES :-)
    * If you use your constants inside string literals ("MY_CONSTANT"),
      sqlpp will replace them also.
ENDHELP
}

#########################################
# The program
#########################################

if ((0 <= $#ARGV) and (('--help' eq $ARGV[0]) or ('-h' eq $ARGV[0]))) {
    printHelp();
} else {
    my  $inputFile = undef;
    my $outputFile = undef;

    for (my $argp = 0; ($argp <= $#ARGV); $argp++) {
        my $arg = $ARGV[$argp];
        if ('--verbose' eq $arg) {
            $verbose = 1;
        } elsif (('-i' eq $arg) and ($argp < $#ARGV)) {
             $inputFile = $ARGV[++$argp];
        } elsif (('-o' eq $arg) and ($argp < $#ARGV)) {
            $outputFile = $ARGV[++$argp];
        }
    }

    my @newContents = parseFile(($inputFile ? rel2abs($inputFile) : undef), 1);
    my $newContents = join('', @newContents);

    if ($outputFile) {
        open(FH, '>', $outputFile) or fatal('Cannot write to file! ' . $outputFile);
        binmode(FH, ':utf8');
        print(FH $newContents);
        close(FH) or fatal("Error closing file: $! . File: $outputFile");
    } else {
        printf($newContents);
    }
}
