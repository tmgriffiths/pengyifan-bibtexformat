package ParseBibTeX;

####################################################################################################
#
# Package:         ParseBibTeX
#
# Author:          Benjamin Bulheller
#
# Website:         www.bulheller.com
#
# Mail address:    webmaster.-at-.bulheller.com
#
# Version:         $Revision: 4896 $, $Date: 2011-02-18 21:39:55 +0100 (Fri, 18 Feb 2011) $
#
# Date:            March 2009
#
#
# Licence:         This program is free software: you can redistribute it and/or modify
#                  it under the terms of the GNU General Public License as published by
#                  the Free Software Foundation, either version 3 of the License, or
#                  (at your option) any later version.
#
#                  This program is distributed in the hope that it will be useful,
#                  but WITHOUT ANY WARRANTY; without even the implied warranty of
#                  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#                  GNU General Public License for more details.
#
#                  You should have received a copy of the GNU General Public License
#                  along with this program.  If not, see http://www.gnu.org/licenses/.
#
# Routines:
#
#     ParseBibTeX ($Library, $Content) # returns the complete library as hash and array items
#     WriteBibTeX ($Library, $OutFile, $NewLines) # writes the library to the given output file
#
#     ParseAuthor ($Item, $Line)      # parses the author field
#     ParseTitle ($Item, $Line)       # extracts the title, considering additional enclosing braces
#     ParsePages ($Item, $Line)       # extracts and parses the page or pages range
#     ParseYear ($Item, $Line)        # extracts the full year (4 digits) and the short year (2 digits)
#     ParseFile ($Item, $Line)        # splits up the file field (used by JabRef)
#     ParseLocalURL ($Item, $Line)    # splits up the local-url field
#
#     FieldName ($Line)               # extracts the name of a certain field (all before the equal sign)
#     FieldContent ($Line)            # extracts the value of a certain field (all between the braces)
#     GetDelimiter ($Line, $Side)     # determines the field delimiter used for the entry (" or {})
#     ReplaceType ($Item, $Old, $New) # replaces field names in the {Entry} and the {Fields} hash items
#     DeleteField ($Item, $Field)     # deletes a field in the {Entry} and the {Fields} hash items
#     GetIndex (Item, $Field)         # returns the index in the entry array of a specific field
#
####################################################################################################

use strict;                         # always use this!!!
use FindBin qw/$Bin/;               # set $Bin to the script's directory
use lib $Bin;                       # add the script's directory to the library path
use lib "$ENV{HOME}/bin/perllib";   # add ~/bin/perllib to the library path
use Data::Dumper;                   # for printing arrays and hashes
use DebugPrint;                     # handy for printing variables during debgging

require Exporter;
our @ISA    = qw( Exporter );

our @EXPORT = qw( ParseBibTeX WriteBibTeX ParseAuthor ParseTitle ParsePages ParseYear ParseFile ParseLocalURL
                  GetDelimiter FieldName FieldContent ReplaceType DeleteField GetIndex
						$ITEMTYPE $FIELDTYPE $FIELDSTART $FIELDEND );

our $ERROR  = "\nERROR (ParseBibTeX.pm)";

# All special characters in the following RegEx-snippets have to be double-escaped, i.e. \{ => \\{

# The start of a new BibTeX entry with the @item:
#    ^\s*        At the beginning of the line optional blanks or tabs (*= zero or more times)
#    \@          an @
#    [\w-]+      multiple word characters or dashes (...) => saved into $1
#    \s*         zero or more blanks or tabs
#    \{          an opening brace {
our $ITEMTYPE   = "^\\s*\\@([\\w-]+)\\s*\\{";

# a BibTeX field type such as 'Author =' or 'Title ='
#    \s*         zero or more spaces/tabs
#    [\w-]+      multiple word characters or dashes
#    \s*=\s*     an = possibly surrounded by blanks
#    [{\"]       optionally either an opening brace { or double quotes ", depending on the field delimiters
our $FIELDTYPE  = "\\s*[\\w-]+\\s*=\\s*[{\"]?";

# Just a shortcut for stuff that could be before a BibTeX field type (before 'Author'),
# optional multiple blanks at the beginning of the line
our $FIELDSTART = "^\\s*";

# Stuff after a BibTeX field type (after 'Author')
#    \s*=\s*     an = possibly surrounded by blanks
#    [{\"]?      optionally either an opening brace { or double quotes ", depending on the field delimiters
our $FIELDEND   = "\\s*=\\s*[{\"]?";


####################################################################################################


sub ParseBibTeX { # creates an array of BibTeX items and also separates the single fields
	my $Library = shift;
	my $Content = shift;
	
	my ($Line, $Label, $RefType, $Field, $Counter, @Fields, $i, $Author, $UrlWarning);
	
	if ($Content =~ m/^ARRAY/) { # if it is a reference to an array
		# remove some garbage added by EndNote to the beginning of the first line
		$Content->[0] =~ s/^﻿//;
	}
	# check for the existence of file, and try the .bib extension
	elsif (-f $Content or -f "$Content.bib") {
		if (-f "$Content.bib") { $Content = "$Content.bib" }

		open BIBTEX, "<$Content" or die "$ERROR: Could not open file $Content: $!";
		my @Content = <BIBTEX>;
		close BIBTEX;

		$Content = \@Content;
	}
	else {
		print STDERR "$ERROR: The second parameter for the routine ParseBibTeX must either be a reference\n" .
		print STDERR "                       to an array with the content of the BibTeX database or a string\n" .
		print STDERR "                       with the filename. If the extension is .bib, it can be omitted.\n\n";
		exit 12;
	}
	
	# If the file was created under Windows, the line feed information may get lost and only
	# ^M characters show up instead of actual newlines. Hence, the file content is read as a
	# single line. If the read array only contains a single line and also ^M characters are
	# found, this line is split into multiple lines at these ^Ms.
	# Note that between the slashes of the last RegEx there is actually this special character
	# (displayed as ^M in vim under Linux & Mac OS). However, it may not be displayed always,
	# depending on the used editor and OS.
	if ($Content->[0] and $#{$Content} == 0 and $Content->[0] =~ m//) { 
		my @Lines = split /+/, $Content->[0];
		$Content = \@Lines;
	}
	
	while ( @{$Content} ) {             # while lines are found
		$Line = shift @{$Content};       # read the next line
		$Line =~ s/^[\s\t]+|[\s\t]+$//g; # remove leading and trailing blanks or tabs
		
		if ($Line =~ m/^@/) {            # if the line starts with "@"
			my $Item = {};                # create an  anonymous hash
			
			# read the reference type, everything one char after the @ until one char before the first {
			$RefType = substr $Line, index ($Line, "@") + 1, index ($Line, "{") - 1;
			$Item->{RefType} = $RefType;
			
			# A @string entry is always on a single line and these entries are treated differently than
			# other items.
			if ($Line =~ m/\@STRING/i) {
				$Line = &ReadMultiLine ($Line, $Content);
				$Item->{Fields}{string} = &FieldContent ($Line);
				push @{$Item->{Entry}}, $Line;
				push @{$Library}, $Item;
				next;
			}
			elsif ($Line =~ m/\@COMMENT/i) {
				$Line = &ReadMultiLine ($Line, $Content);
				$Item->{Fields}{comment} = &FieldContent ($Line);
				push @{$Item->{Entry}}, $Line;
				push @{$Library}, $Item;
				next;
			}
			else {
				push @{$Item->{Entry}}, $Line;
			}
			
			# if the current line ends not with a comma and
			# the next line ($Content->[0]) starts with a label, which is the case if it
			#    ^\s*        starts with zero or more blanks,
			#    [^\s\t,]+   a string containing all possible characters but no blanks and commas
			#    ,           which is followed by a comma
			if ( ($Line !~ m/,$/) and ($Content->[0] =~ m/^\s*([^\s\t,]+),/) ) {
				$Label = $Content->[0];         # save the label
				$Label =~ s/,$//;               # remove the trailing comma
				
				$Line = $Line . $Content->[0];  # merge the current end the next line
				shift @{$Content};              # delete the next line from $Content
			}
			# if the line ends with a comma and the next line does not start with a label
			elsif ( ($Line =~ m/,$/) and ($Content->[0] !~ m/^\s*([^\s\t,]+),/) ) {
				$Label = $Line;
				
				# cut out the label from the line
				#   ^@        starting with an @ symbol
				#   [^{]+     then multiple characters except a {
				#   \{        then the {
				#   ([^,]+)   then multiple characters exept , (= backreference $1)
				#   ,         and finally the comma at the end of the line
				$Label =~ s/^@[^{]+\{([^,]+),$/$1/;
			}
			else {
				$Label = "";
			}
			
			if ($Label) { $Item->{Label} = $Label }
			
			# everything between the last @ and the following @ is added to the current item
			until (not @{$Content} or $Content->[0] =~ m/$FIELDSTART\@/) {
				$Line = shift @{$Content};
				$Line =~ s/^[\s\t]+|[\s\t]+$//g;      # remove leading and trailing blanks or tabs
				
				if (not $Line) { next }  # skip empty lines
				$Line = &ReadMultiLine ($Line, $Content);
				
				if ($Line =~ m/$FIELDTYPE/i) {
					$Field = &FieldName ($Line);     # extract the field name
					$Field = lc $Field;              # format the field name lowercase
					$Item->{Fields}{$Field} = &FieldContent ($Line);
					
					# now $Field contains the name of the current field in lowercase
					if ($Field eq "author")    { &ParseAuthor   ($Item, $Line); }
					if ($Field eq "title")     { &ParseTitle    ($Item, $Line); }
					if ($Field eq "year")      { &ParseYear     ($Item, $Line); }
					if ($Field eq "pages")     {
						&ParsePages    ($Item, $Line);
						$Line =~ s/---/--/;  # replace --- with --
					}
					if ($Field eq "file")      { &ParseFile     ($Item, $Line); }
					if ($Field eq "local-url") { &ParseLocalURL ($Item, $Line); }
				}
				
				push @{$Item->{Entry}}, $Line;
			} # of until (not @{$Content} or $Content->[0] =~ m/^@/)
			
			# remove trailing empty lines from the entry (these will be added later
			# by sub WriteBibTeX automatically)
			while ( $Item->{Entry}[ $#{$Item->{Entry}} ] =~ m/^\s*$/ ) {
				pop @{$Item->{Entry}};
			}
			
			# remove trailing blanks from the very last item (this includes line feeds,
			# which are added later on by WriteBibTeX
			$Item->{Entry}[ $#{$Item->{Entry}} ] =~ s/\s*$//g;
			
			# Check if the last line in the entry contains the closing brace (and only that). If the closing
			# brace was added to the last item field (such as url=) and this is removed using -s, the closing
			# brace would be missing. Therefore, the closing brace is forced into the last line
			if ($Item->{Entry}[$#{$Item->{Entry}}] !~ m/^([\s\t]+)?\}([\s\t]+)?$/) {
				# remove the last brace of the last entry
				$Item->{Entry}[$#{$Item->{Entry}}] =~ s/}([\s\t]+)?$//;
				# add the closing brace
				push @{$Item->{Entry}}, "}";
				
				# the last brace has also been included in the last field content
				# (see comment in sub FieldContent) and has to be replaced here.
				$Field = lc &FieldName ($Item->{Entry}[$#{$Item->{Entry}}-1]);
				$Item->{Fields}{$Field} =~ s/\}$//;
			}
			
			push @{$Library}, $Item;
		} # of if ($Line =~ m/^@/) {            # if the line starts with "@"
		# dp ($Library);
	} # of while ( @{$Content} )
} # of sub ParseBibTeX


####################################################################################################


sub WriteBibTeX { # writes out a BibTeX library
	my $Library  = shift;
	my $OutFile  = shift;
	my $NewLines = shift;
	my ($Item);
	
	if (not defined $NewLines) { $NewLines = 2 }
	
	open FILE, ">$OutFile" or die "$ERROR: Could not write file $OutFile: $!";
	
	while (@{$Library}) {
		$Item = shift @{$Library};
		
		print FILE join "\n", @{$Item->{Entry}};
		
		# if the reference type of the current item is @string
		if ($Item->{RefType} =~ m/string/i
		     # and the reference type of the next item is string, too
		     and $Library->[0]{RefType} =~ m/string/i) {
			# only add a single line feed, no additional empty lines
			# between the @string defintions
			print FILE "\n";
		}
		else {
			# For all other entries (including occasions when a normal item
			# precedes a string or follows it, i.e. before or after a @string
			# entry ot block)
			# add the configured number of line feeds. Mind that the "0" is just
			# the end of line of the entry and, if 2 empty lines are configured,
				# iterations 1 and 2 would account for them.
			for (0 .. $NewLines) { print FILE "\n" }
		}
	}
	
	close FILE;
} # of sub WriteBibTeX


####################################################################################################


sub ParseAuthor { # parses the author field
	my $Item = shift;
	my $Line = shift;
	
	my ($FirstAuthor, $Authors, @Authors, @Fields, $Field, $AuthSep);
	
	$Authors = &FieldContent ($Line);
	$Authors =~ s/\n/ /g;               # replace line feeds with blanks
	$Item->{Fields}{author} = $Authors;
	
	# now cut out the first author, which is needed for the label generation
	if ($Authors =~ m/ and /) {    # if there is more than one author
		$Authors =~ s/^[\s\t]+|[\s\t]+$//g;  # remove leading and trailing blanks and tabs (problem with split otherwise)
		@Fields = split /\s+and\s+/, $Authors;
		
		# check for "and others"
		if ($Fields[$#Fields] =~ m/^others$/i) { pop @Fields }
		
		# create a fresh copy of the split up authors for $Item->{AuthorList}
		my @AuthorList = @Fields;
		$Item->{AuthorList} = \@AuthorList;
		
		$FirstAuthor = $Fields[0];
	}
	else { # if it's only a single author
		$FirstAuthor = $Authors;
		
		# create a fresh copy of the split up authors for $Item->{AuthorList}
		my @AuthorList = ($FirstAuthor);
		$Item->{AuthorList} = \@AuthorList;
	} # if ($Authors =~ m/ and /)
	
	# now the format could be "Firstname Lastname" or "Lastname, Firstname"
	if ($FirstAuthor =~ m/,/) { # if the first field contains a comma
		# take everything from the start until the first comma
		$FirstAuthor = substr $FirstAuthor, 0, (index $FirstAuthor, ",");
	}
	else {
		# split the first author at multiple blanks
		my @BlankFields = split /\s+/, $FirstAuthor;
		
		$FirstAuthor = pop @BlankFields; # take the last field as a first try
		
		# This would split "Rico Mi{\v c}eti{\v c}ez" into the wrong parts. It is very unlikely
		# (hopefully impossible, otherwise please send a mail) that two letters follow the first
		# one, e.g. {\v ab}. Therefore, if a letter and a brace are at the beginning of the last 
		# field, it it is assumed that it is a fragment
		until (not @BlankFields or $FirstAuthor !~ m/^[\w]\}/) {
			$Field = pop @BlankFields;
			$FirstAuthor = "$Field $FirstAuthor";
		}
	}
	
	# copy from position of the first "{"+1, to the next comma
	# $FirstAuthor =~ s/\s//g;           # remove all blanks to merge e.g. "Del Bene" => "DelBene"
	$FirstAuthor =~ s/'//g;              # remove all apostrophes e.g. "van'tHoff" => "vantHoff"
	
	if ($FirstAuthor !~ m/[a-z]/g) {     # if there are only uppercase letters
		$FirstAuthor = lc $FirstAuthor;
		$FirstAuthor =~ s/\b(\w)/\u$1/g;  # capitalize first letter
	}
	
	$Item->{FirstAuthor} = $FirstAuthor;
} # of sub ParseAuthor


####################################################################################################


sub ParseTitle { # extracts the title, taking additional enclosing braces into account
	my $Item = shift;
	my $Line = shift;
	
	$Item->{Fields}{title} = &FieldContent ($Line);
	
	# Remove additional braces at the beginning and the end of the title (in case the title was
	# enclosed in double braces). This is only done if there is a brace at the beginning AND the end
	# of the string to account for the fact that there could be a single protected word at the
	# beginniging or the end of the title
	if ($Item->{Fields}{title} =~ m/^([\s\t]+)?\{/ and $Item->{Fields}{title} =~ m/\}([\s\t]+)?$/) {
		$Item->{Fields}{title} =~ s/^([\s\t]+)?\{|\}([\s\t]+)?$//g;
	}
} # of sub ParseTitle


####################################################################################################


sub ParsePages { # extracts and parses the page or pages range
	my $Item = shift;
	my $Line = shift;
	
	my ($Pages, $StartPage, $EndPage);
	
	if (not $Line) { return }
	
	# cut out the original "pages" string
	$Pages = &FieldContent ($Line);
	$Pages =~ s/-+$//;            # remove trailing dashes, this is rare but causes problems if present
	$Item->{Fields}{pages} = $Pages;
	
	if (not $Pages or             # no pages are given and the field content is empty
		 $Pages =~ m/[()]/) {      # brackets contained, e.g. 13645(1-2)
		$Item->{FirstPage} = "";
		$Item->{EndPage} = "";
		return $Line;
	}
	
	$Pages =~ s/\s//g;     # remove all blanks from the pages string

	if ($Pages !~ m/-/) {  # if no dash is contained
		$StartPage = $Pages;
		$EndPage   = "";
	}
	else { # ther is a dash (i.e. a page range is given)
		# The page "numbers" may actually contain letters as some journals have
		# page numbers like "THEO1234"
		$Pages =~ s/^[\W]+|[\W]+$//; # cut away leading or trailing non-word characters
		($StartPage, $EndPage) = split /-+/, $Pages, 2;
		# Debug output
		# printf "%15s  =>  %10s  %10s\n", $Pages, $StartPage, $EndPage;
	}
	
	$Item->{StartPage} = $StartPage;
	$Item->{EndPage}   = $EndPage;
} # of sub ParsePages


####################################################################################################


sub ParseYear { # extracts the full year (4 digits) and the short year (2 digits)
	my $Item = shift;
	my $Line = shift;
	
	# read the full year as given
	$Item->{Year} = &FieldContent ($Line);
	$Item->{Year} =~ s/^[{"]|["}]$//g; # remove delimiters at the start and end
	
	if (length $Item->{Year} == 2) {
		$Item->{ShortYear} = $Item->{Year};
	}
	elsif (length $Item->{Year} == 4) {
		$Item->{ShortYear} = substr $Item->{Year}, 2, 2;
	}
} # of sub ParseYear


####################################################################################################


sub ParseFile { # splits up the file field (used by JabRef)
	my $Item = shift;
	my $Line = shift;
	
	my ($Original, @Files, $File, @Fields);
	
	$Original = &FieldContent ($Line);
	
	# first split all single file entries (separated by commas
	@Files   = split ";", $Original;
	
	# now split each file entry at colons, Comment:URL:Type
	foreach $File ( @Files ) {
		@Fields = split ":", $File;
		
		# make sure that there are no undefinded values
		if (not defined $Fields[0]) { $Fields[0] = "" }
		if (not defined $Fields[1]) { $Fields[1] = "" }
		if (not defined $Fields[2]) { $Fields[2] = "" }
		
		push @{$Item->{File}}, { Comment => $Fields[0], URL => $Fields[1], Type => $Fields[2] };
	}
	
	return $Line;
} # of sub ParseFile


####################################################################################################


sub ParseLocalURL { # splits up the local-url field and converts to JabRef format if requested
	my $Item = shift;
	my $Line = shift;
	
	# save the original, unchanged local-url field
	$Item->{LocalURL} = &FieldContent ($Line);
	
	return $Line;
} # of sub ParseLocalURL


####################################################################################################


sub FieldName { # extracts the name of a certain field (everything before the equal sign)
	my $Line = shift;
	my $Field;
	
	$Field = substr $Line, 0, index ($Line, "=");  # cut everything from start to the "="
	$Field =~ s/[\s\t]//g;                         # remove blanks and tabstops
	
	return $Field;
} # of sub FieldName


####################################################################################################


sub FieldContent { # extracts the value of a certain field (everything between the braces)
	my $Line = shift;
	my ($Delimiter, $Prefix, $Suffix, $Value);
	
	# A special case may cause problems: If the last line contains the finalizing brace:
	#       year = {1999}}
	# This will lead to "1999}". Dealing with it here is problematic, for example:
	#       title = {Lorem ipsum specia{\'l}}
	#       }
	# Therefore, the brace is being dealt with in ParseBibTeX when it is known whether it
	# is indeed the last line of the entry
	
	# cut out everything between the first [{"} and the last [}"]
	$Delimiter = &GetDelimiter ($Line, "left", "FieldContent");
	
	if ($Delimiter) {
		$Prefix = substr $Line, 0, index ($Line, $Delimiter)+1;
		$Value  = substr $Line, index ($Line, $Delimiter)+1;
	}
	else {
		$Prefix = substr $Line, 0, index ($Line, "=")+1;
		$Value  = substr $Line, index ($Line, "=")+1;
	}
	
	$Delimiter = &GetDelimiter ($Line, "right", "FieldContent");
	
	if ($Delimiter) {
		$Value  = substr $Value, 0, rindex ($Value, "$Delimiter");
		$Suffix = substr $Line, rindex ($Line, $Delimiter);
	}
	else {
		$Value  = substr $Value, 0, rindex ($Value, ",");
		$Suffix = substr $Line, rindex ($Line, ",");
	}
	
	$Value =~ s/^[\s\t]+|[\s\t]+$//g;   # remove leading and trailing blanks
	return $Prefix, $Suffix, $Value;
} # of sub FieldContent


####################################################################################################


sub GetDelimiter { # determines the field delimiter used for the entry (" or {})
	my $Line = shift;
	my $Side = shift;
	my $Code = shift;
	my $Delimiter;
	
	# if an error code is given by the calling subroutine, add it surrounded by brackets
	if ($Code) { $Code = " ($Code)" }
	      else { $Code = ""         }
	
	# ^           beginning of the line
	# ([\s\t]+)?  multiple number of blanks or tabs, optional
	# [\w-]+      a number of word character or dashes (for local-url)
	# ([\s\t]+)?  multiple number of blanks or tabs, optional
	# =           an equal sign
	# ([\s\t]+)?  multiple number of blanks or tabs, optional
	# \{          a left brace or (in the elsif branch below) quotation marks
	if ($Line =~ m/^([\s\t]+)?[\w-]+([\s\t]+)?=([\s\t]+)?\{/) {
		if    ($Side eq "left" ) { return "{" }
		elsif ($Side eq "right") { return "}" }
		                    else { return ""  }
	}
	elsif ($Line =~ m/^([\s\t]+)?[\w-]+([\s\t]+)?=([\s\t]+)?\"/) {
		return "\"";  # there's no left or right here, all is equal
	}
	# ^           beginning of the line
	# ([\s\t]+)?  multiple number of blanks or tabs, optional
	# @[\w-]+     an @ followed by a number of word character or dashes (for e.g. @comment)
	# \{[^\}]+    an opening brace followed by multiple characters that are not closing braces
	# \}          a final closing brace
	elsif ($Line =~ m/^([\s\t]+)?\@[\w-]+\{[^\}]+\}/) {
		if    ($Side eq "left" ) { return "{" }
		elsif ($Side eq "right") { return "}" }
		                    else { return ""  }
	}
	else {
		return "";
	}
} # of sub GetDelimiter


####################################################################################################


sub ReplaceType { # replaces field names in the {Entry} and the {Fields} hash items
	my $Item = shift;
	my $Old  = shift;
	my $New  = shift;
	my $Type;
	
	# if a specific BibTeX type was given (such as @article)
	if ($Old =~ m/^\@/) {
		$Type = lc $New;               # convert the new type lowercase
		$Type =~ s/\@//g;              # remove the leading @
		$Item->{RefType} = $Type;      # save it to the RefType hash key
		
		$Item->{Entry}[0] =~ s/$Old/$Type/i;
	}
	# if, more general, the BibTeX type
	elsif ($Old eq "RefType") {
		$Old  = $Item->{RefType};     # read the old reference type to replace it
		$Type = lc $New;              # convert the new type lowercase
		$Type =~ s/\@//g;             # remove the leading @
		$Item->{RefType} = $Type;
		$Item->{Entry}[0] =~ s/$Old/$Type/i;
	}
	# if a field is given that is present in the entry
	elsif ($Item->{Fields}{$Old}) {
		# Check if the new field exists already. If so, then delete it in the {Entry}
		# array as otherwise there would be a double entry:
		#   - Assume the instruction
		#         REPLACE  doi, pages
		#   - And the entry
		#         doi   = { foo }
		#         pages = { bar }
		#   - While in the {Fields}-hash "pages" will simply be replaced by "doi", in
		#     the array the index of the old "doi" entry is changed "to pages, leaving
		#     the old pages entry still in there:
		#         pages = { foo }
		#         pages = { bar }
		#     
		if (defined $Item->{Fields}{$New}) {
			DeleteField ($Item, $New);
		}
		
		$Item->{Fields}{$New} = $Item->{Fields}{$Old};
		delete $Item->{Fields}{$Old};
		
		# this is the index of the old entry, 
		my $Index = &GetIndex ($Item, $Old);
		if ($Index) {
			$Item->{Entry}[$Index] =~ s/$FIELDSTART$Old/$New/i;
		}
	}
} # of sub ReplaceType


####################################################################################################


sub ReplaceValue { # replaces a field value in the {Entry} and the {Fields} hash items
	my $Item     = shift;
	my $Field    = shift;
	my $NewValue = shift;
	#######################################
	# Added $Delimiter Variable
	#######################################
	my ($Index, $OldEntry, $Delimiter);
	
	# all hash keys in $Item->{Fields} are lowercase
	$Field = lc $Field;
	if (not $Item->{Fields}{$Field}) { return }
	else {
		$Item->{Fields}{$Field} = $NewValue;
	}

	# Tackle the {Entry} line
	# get the number of the local-url line in $Item->{Entry} (this is printed out later}
	$Index = GetIndex ($Item, "local-url");
	
	
	# get the exact value of the local-url entry
	$OldEntry = FieldContent ($Item->{Entry}[$Index]);

	# replace the old entry with the new one while leaving the rest exactly as it was before
	if ($Item->{Entry}[$Index] =~ m/$OldEntry/i) { die }
	$Item->{Entry}[$Index] =~ s/$OldEntry/$Item->{LocalURL}/;
	# dp ($Index, $Item->{Entry}[$Index]);
} # of sub ReplaceValue


####################################################################################################


sub DeleteField { # deletes a field in the {Entry} and the {Fields} hash items
	my $Item  = shift;
	my $Field = shift;
	
	if (defined $Item->{Fields}{$Field}) {
		delete $Item->{Fields}{$Field};
		
		my $Index = &GetIndex ($Item, $Field);
		# delete the line from the array $Item->{Entry}
		if ($Index) { splice @{$Item->{Entry}}, $Index, 1; }
	}
} # of sub DeleteField


####################################################################################################


sub GetIndex { # returns the index in the entry array of a specific field
	my $Item  = shift;
	my $Field = shift;
	my ($Index, $Line);
	
	if (not $Item->{Entry}) { return undef }
	
	$Index = 0;
	
	foreach $Line ( @{$Item->{Entry}} ) {
		if ($Line =~ m/$FIELDSTART($Field)$FIELDEND/i) { return $Index }
		                                          else { ++$Index      }
	}
	
	return undef;  # if the field hasn't been found
} # of sub GetIndex


####################################################################################################


sub ReadMultiLine { # checks whether the following lines actually belong to the current entry
	my $Line    = shift;  # the line that had just been read
	my $Content = shift;  # the remainder of the content to be parsed
	my $NewLine;
	
	# combine multiple line entries, read the following lines until the entry is complete
	# until the line ends with } or }, - mind that the former match would also be true if an
	# accented or case-protected word is at the end of the line
	
	# check for
	# []"]?        either one or none of the two possible field delimiters at the end of the string
	# ([\s\t]+)?   optional multiple blanks or tabs
	# ,?$          optional comma at the end of the string
	until ($Line =~ m/[}"]?([\s\t]+)?,?$/ and      # until the line ends with } or },
	       (not $Content->[0]                      # and no lines are left
		     or $Content->[0] =~ m/$ITEMTYPE/       # or the next line is a BibTeX item, e.g. "@book"
		     or $Content->[0] =~ m/$FIELDTYPE/      # or the next line is a BibTeX field, e.g. " journal = {"
		     # or the next line contains just a single brace } (the end of the current item)
		     or $Content->[0] =~ m/^([\s\t]+)?}([\s\t]+)?$/) ) {
		$NewLine = shift @{$Content};               # read the next line from the original library content
		$NewLine =~ s/^[\s\t]+|[\s\t]+$//g;         # remove leading and trailing blanks or tabs
		
		# leave a line feed between the lines (and a blank, just in case)
		$Line = $Line . " \n" . $NewLine;
	}
	
	return $Line;
} # of sub ReadMultiLine


####################################################################################################


1;
