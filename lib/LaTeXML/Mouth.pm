# /=====================================================================\ #
# |  LaTeXML::Mouth                                                     | #
# | Analog of TeX's Mouth: Tokenizes strings & files                    | #
# |=====================================================================| #
# | Part of LaTeXML:                                                    | #
# |  Public domain software, produced as part of work done by the       | #
# |  United States Government & not subject to copyright in the US.     | #
# |---------------------------------------------------------------------| #
# | Bruce Miller <bruce.miller@nist.gov>                        #_#     | #
# | http://dlmf.nist.gov/LaTeXML/                              (o o)    | #
# \=========================================================ooo==U==ooo=/ #

#**********************************************************************
# LaTeXML::Mouth
#    Read TeX Tokens from a String.
#**********************************************************************
package LaTeXML::Mouth;
use strict;
use warnings;
use LaTeXML::Global;
use LaTeXML::Token;
use LaTeXML::Util::Pathname;
use base qw(LaTeXML::Object);

# Factory method;
# Create an appropriate Mouth
# options are quiet, atletter, content
sub create {
  my ($class, $source, %options) = @_;
  my $type;
  if    ($options{content}) { $type = 'cached'; }
  elsif (!defined $source)  { $type = 'empty'; }
  else                      { $type = pathname_protocol($source); }
  my $newclass = "LaTeXML::Mouth::$type";
  if (!$class->can('new')) {    # not already defined somewhere?
    require "LaTeXML/Mouth/$type.pm"; }
  return $newclass->new($source, %options); }

sub new {
  my ($class, $string) = @_;
  $string = q{} unless defined $string;
  my $self = bless { source => "Anonymous String", shortsource => "String" }, $class;
  $self->openString($string);
  $self->initialize;
  return $self; }

sub openString {
  my ($self, $string) = @_;
  $$self{string} = $string;
  $$self{buffer} = [(defined $string ? splitLines($string) : ())];
  return; }

sub initialize {
  my ($self) = @_;
  $$self{lineno} = 0;
  $$self{colno}  = 0;
  $$self{chars}  = [];
  $$self{nchars} = 0;
  if ($$self{notes}) {
    $$self{note_message} = "Processing " . ($$self{fordefinitions} ? "definitions" : "content")
      . " " . $$self{source};
    NoteBegin($$self{note_message}); }
  if ($$self{fordefinitions}) {
    $$self{saved_at_cc}            = $STATE->lookupCatcode('@');
    $$self{SAVED_INCLUDE_COMMENTS} = $STATE->lookupValue('INCLUDE_COMMENTS');
    $STATE->assignCatcode('@' => CC_LETTER);
    $STATE->assignValue(INCLUDE_COMMENTS => 0); }
  return; }

sub finish {
  my ($self) = @_;
  $$self{buffer} = [];
  $$self{lineno} = 0;
  $$self{colno}  = 0;
  $$self{chars}  = [];
  $$self{nchars} = 0;
  if ($$self{fordefinitions}) {
    $STATE->assignCatcode('@' => $$self{saved_at_cc});
    $STATE->assignValue(INCLUDE_COMMENTS => $$self{SAVED_INCLUDE_COMMENTS}); }
  if ($$self{notes}) {
    NoteEnd($$self{note_message}); }
  return; }

# This is (hopefully) a platform independent way of splitting a string
# into "lines" ending with CRLF, CR or LF (DOS, Mac or Unix).
# Note that TeX considers newlines to be \r, ie CR, ie ^^M
sub splitLines {
  my ($string) = @_;
  $string =~ s/(?:\015\012|\015|\012)/\r/sg;    #  Normalize remaining
  return split("\r", $string); }                # And split.

# This is (hopefully) a correct way to split a line into "chars",
# or what is probably more desired is "Grapheme clusters" (even "extended")
# These are unicode characters that include any following combining chars, accents & such.
# I am thinking that when we deal with unicode this may be the most correct way?
# If it's not the way XeTeX does it, perhaps, it must be that ALL combining chars
# have to be converted to the proper accent control sequences!
sub splitChars {
  my ($line) = @_;
  return $line =~ m/\X/g; }

sub getNextLine {
  my ($self) = @_;
  return unless scalar(@{ $$self{buffer} });
  my $line = shift(@{ $$self{buffer} });
  return (scalar(@{ $$self{buffer} }) ? $line . "\r" : $line); }    # No CR on last line!

sub hasMoreInput {
  my ($self) = @_;
  return ($$self{colno} < $$self{nchars}) || scalar(@{ $$self{buffer} }); }

# Get the next character & it's catcode from the input,
# handling TeX's "^^" encoding.
# Note that this is the only place where catcode lookup is done,
# and that it is somewhat `inlined'.
sub getNextChar {
  my ($self) = @_;
  if ($$self{colno} < $$self{nchars}) {
    my $ch = $$self{chars}->[$$self{colno}++];
    my $cc = $$STATE{table}{catcode}{$ch}[0];    # $STATE->lookupCatcode($ch); OPEN CODED!
    if ((defined $cc) && ($cc == CC_SUPER)       # Possible convert ^^x
      && ($$self{colno} + 1 < $$self{nchars}) && ($ch eq $$self{chars}->[$$self{colno}])) {
      my ($c1, $c2);
      if (($$self{colno} + 2 < $$self{nchars})    # ^^ followed by TWO LOWERCASE Hex digits???
        && (($c1 = $$self{chars}->[$$self{colno} + 1]) =~ /^[0-9a-f]$/)
        && (($c2 = $$self{chars}->[$$self{colno} + 2]) =~ /^[0-9a-f]$/)) {
        $ch = chr(hex($c1 . $c2));
        splice(@{ $$self{chars} }, $$self{colno} - 1, 4, $ch);
        $$self{nchars} -= 3; }
      else {                                      # OR ^^ followed by a SINGLE Control char type code???
        my $c  = $$self{chars}->[$$self{colno} + 1];
        my $cn = ord($c);
        $ch = chr($cn + ($cn > 64 ? -64 : 64));
        splice(@{ $$self{chars} }, $$self{colno} - 1, 3, $ch);
        $$self{nchars} -= 2; }
      $cc = $STATE->lookupCatcode($ch); }
    $cc = CC_OTHER unless defined $cc;
    return ($ch, $cc); }
  else {
    return (undef, undef); } }

sub stringify {
  my ($self) = @_;
  return "Mouth[<string>\@$$self{lineno}x$$self{colno}]"; }

#**********************************************************************
sub getLocator {
  my ($self, $length) = @_;
  my ($l, $c) = ($$self{lineno}, $$self{colno});
  if ($length && ($length < 0)) {
    return "at $$self{shortsource}; line $l col $c"; }
  elsif ($length && (defined $l || defined $c)) {
    my $msg   = "at $$self{source}; line $l col $c";
    my $chars = $$self{chars};
    if (my $n = $$self{nchars}) {
      $c = $n - 1 if $c >= $n;
      my $c0 = ($c > 50      ? $c - 40 : 0);
      my $cm = ($c < 1       ? 0       : $c - 1);
      my $cn = ($n - $c > 50 ? $c + 40 : $n - 1);
      my $p1 = ($c0 <= $cm ? join('', @$chars[$c0 .. $cm]) : ''); chomp($p1);
      my $p2 = ($c <= $cn  ? join('', @$chars[$c .. $cn])  : ''); chomp($p2);
      $msg .= "\n  " . $p1 . "\n  " . (' ' x ($c - $c0)) . '^' . ' ' . $p2; }
    return $msg; }
  else {
    return "at $$self{source}; line $l col $c"; } }

sub getSource {
  my ($self) = @_;
  return $$self{source}; }

#**********************************************************************
# See The TeXBook, Chapter 8, The Characters You Type, pp.46--47.
#**********************************************************************

sub handle_escape {    # Read control sequence
  my ($self) = @_;
  # NOTE: We're using control sequences WITH the \ prepended!!!
  my $cs = "\\";       # I need this standardized to be able to lookup tokens (A better way???)
  my ($ch, $cc) = $self->getNextChar;
  # Knuth, p.46 says that Newlines are converted to spaces,
  # Bit I believe that he does NOT mean within control sequences
  $cs .= $ch;
  if ($cc == CC_LETTER) {    # For letter, read more letters for csname.
    while ((($ch, $cc) = $self->getNextChar) && $ch && ($cc == CC_LETTER)) {
      $cs .= $ch; }
    $$self{colno}--; }
  if (($cc == CC_SPACE) || ($cc == CC_EOL)) {    # We'll skip whitespace here.
                                                 # Now, skip spaces
    while ((($ch, $cc) = $self->getNextChar) && $ch && (($cc == CC_SPACE) || ($cc == CC_EOL))) { }
    $$self{colno}-- if ($$self{colno} < $$self{nchars}); }
  return T_CS($cs); }

sub handle_EOL {
  my ($self) = @_;
  # Note that newines should be converted to space (with " " for content)
  # but it makes nicer XML with occasional \n. Hopefully, this is harmless?
  my $token = ($$self{colno} == 1
    ? T_CS('\par')
    : ($STATE->lookupValue('PRESERVE_NEWLINES') ? Token("\n", CC_SPACE) : T_SPACE));
  $$self{colno} = $$self{nchars};    # Ignore any remaining characters after EOL
  return $token; }

sub handle_comment {
  my ($self) = @_;
  my $n = $$self{colno};
  $$self{colno} = $$self{nchars};
  my $comment = join('', @{ $$self{chars} }[$n .. $$self{nchars} - 1]);
  $comment =~ s/^\s+//; $comment =~ s/\s+$//;
  return ($comment && $STATE->lookupValue('INCLUDE_COMMENTS') ? T_COMMENT($comment) : undef); }

# These cache the (presumably small) set of distinct letters, etc
# converted to Tokens.
# Note that this gets filled during runtime and carries over to through Daemon frames.
# However, since the values don't depend on any particular document, bindings, etc,
# they should be safe.
my %LETTER = ();
my %OTHER  = ();
my %ACTIVE = ();

# Dispatch table for catcodes.
my @DISPATCH = (    # [CONSTANT]
  \&handle_escape,    # T_ESCAPE
  T_BEGIN,            # T_BEGIN
  T_END,              # T_END
  T_MATH,             # T_MATH
  T_ALIGN,            # T_ALIGN
  \&handle_EOL,       # T_EOL
  T_PARAM,            # T_PARAM
  T_SUPER,            # T_SUPER
  T_SUB,              # T_SUB
  sub { undef; },     # T_IGNORE (we'll read next token)
  T_SPACE,            # T_SPACE
  sub { $LETTER{ $_[1] } || ($LETTER{ $_[1] } = T_LETTER($_[1])); },    # T_LETTER
  sub { $OTHER{ $_[1] }  || ($OTHER{ $_[1] }  = T_OTHER($_[1])); },     # T_OTHER
  sub { $ACTIVE{ $_[1] } || ($ACTIVE{ $_[1] } = T_ACTIVE($_[1])); },    # T_ACTIVE
  \&handle_comment,                                                     # T_COMMENT
  sub { T_OTHER($_[1]); }    # T_INVALID (we could get unicode!)
);

# Read the next token, or undef if exhausted.
# Note that this also returns COMMENT tokens containing source comments,
# and also locator comments (file, line# info).
# LaTeXML::Gullet intercepts them and passes them on at appropriate times.
sub readToken {
  my ($self) = @_;
  while (1) {    # Iterate till we find a token, or run out. (use return)
                 # ===== Get next line, if we need to.
    if ($$self{colno} >= $$self{nchars}) {
      $$self{lineno}++;
      $$self{colno} = 0;
      my $line = $self->getNextLine;
      if (!defined $line) {    # Exhausted the input.
        $$self{chars}  = [];
        $$self{nchars} = 0;
        return; }
      # Remove trailing space, but NOT a control space!  End with CR (not \n) since this gets tokenized!
      $line =~ s/((\\ )*)\s*$/$1\r/s;
      $$self{chars}  = [splitChars($line)];
      $$self{nchars} = scalar(@{ $$self{chars} });
      while (($$self{colno} < $$self{nchars})
        && (($$STATE{table}{catcode}{ $$self{chars}->[$$self{colno}] }[0] || CC_OTHER) == CC_SPACE)) {
        $$self{colno}++; }

      # Sneak a comment out, every so often.
      if ((($$self{lineno} % 25) == 0) && $STATE->lookupValue('INCLUDE_COMMENTS')) {
        return T_COMMENT("**** $$self{shortsource} Line $$self{lineno} ****"); }
    }
    # ==== Extract next token from line.
    my ($ch, $cc) = $self->getNextChar;
    my $token = $DISPATCH[$cc];
    $token = &$token($self, $ch) if ref $token eq 'CODE';
    return $token if defined $token;    # Else, repeat till we get something or run out.
  }
  return; }

#**********************************************************************
# Read all tokens until a token equal to $until (if given), or until exhausted.
# Returns an empty Tokens list, if there is no input

sub readTokens {
  my ($self, $until) = @_;
  my @tokens = ();
  while (defined(my $token = $self->readToken())) {
    last if $until and $token->getString eq $until->getString;
    push(@tokens, $token); }
  while (@tokens && $tokens[-1]->getCatcode == CC_SPACE) {    # Remove trailing space
    pop(@tokens); }
  return Tokens(@tokens); }

#**********************************************************************
# Read a raw lines; there are so many variants of how it should end,
# that the Mouth API is left as simple as possible.
sub readRawLine {
  my ($self) = @_;
  my $line;
  if ($$self{colno} < $$self{nchars}) {
    $line = join('', @{ $$self{chars} }[$$self{colno} .. $$self{nchars} - 1]);
    # End lines with \n, not CR, since the result will be treated as strings
    $$self{colno} = $$self{nchars}; }
  else {
    $line = $self->getNextLine;
    if (!defined $line) {
      $$self{chars} = []; $$self{nchars} = 0; $$self{colno} = 0; }
    else {
      $$self{lineno}++;
      $$self{chars}  = [splitChars($line)];
      $$self{nchars} = scalar(@{ $$self{chars} });
      $$self{colno}  = $$self{nchars}; } }
  $line =~ s/\s*$//s if defined $line;    # Is this right?
  return $line; }

#**********************************************************************
# LaTeXML::FileMouth
#    Read TeX Tokens from a file.
#**********************************************************************
package LaTeXML::FileMouth;
use strict;
use LaTeXML::Global;
use LaTeXML::Util::Pathname;
use base qw(LaTeXML::Mouth);
use Encode;

sub new {
  my ($class, $pathname) = @_;
  #  my $self =  bless {source=>pathname_relative($pathname,pathname_cwd)}, $class;
  my ($dir, $name, $ext) = pathname_split($pathname);
  my $self = bless { source => $pathname, shortsource => "$name.$ext" }, $class;
  #  $$self{fordefinitions}=1;
  $$self{notes} = 1;
  $self->openFile($pathname);
  $self->initialize;
  return $self; }

sub openFile {
  my ($self, $pathname) = @_;
  my $IN;
  if (!-r $pathname) { Fatal('I/O', $pathname, $self, "File $pathname is not readable."); }
  elsif ((!-z $pathname) && (-B $pathname)) { Fatal('I/O', $pathname, $self, "Input file $pathname appears to be binary."); }
  open($IN, '<', $pathname) || Fatal('I/O', $pathname, $self, "Can't open $pathname for reading", $!);
  $$self{IN}     = $IN;
  $$self{buffer} = [];
  return; }

sub finish {
  my ($self) = @_;
  $self->SUPER::finish;
  if ($$self{IN}) {
    close(\*{ $$self{IN} }); $$self{IN} = undef; }
  return; }

sub hasMoreInput {
  my ($self) = @_;
  #  ($$self{colno} < $$self{nchars}) || $$self{IN}; }
  return ($$self{colno} < $$self{nchars}) || scalar(@{ $$self{buffer} }) || $$self{IN}; }

sub getNextLine {
  my ($self) = @_;
  if (!scalar(@{ $$self{buffer} })) {
    return unless $$self{IN};
    my $fh   = \*{ $$self{IN} };
    my $line = <$fh>;
    if (!defined $line) {
      close($fh); $$self{IN} = undef;
      return; }
    else {
      push(@{ $$self{buffer} }, LaTeXML::Mouth::splitLines($line)); } }

  my $line = (shift(@{ $$self{buffer} }) || '');
  if ($line) {
    if (my $encoding = $STATE->lookupValue('PERL_INPUT_ENCODING')) {
     # Note that if chars in the input cannot be decoded, they are replaced by \x{FFFD}
     # I _think_ that for TeX's behaviour we actually should turn such un-decodeable chars in to space(?).
      $line = decode($encoding, $line, Encode::FB_DEFAULT);
      if ($line =~ s/\x{FFFD}/ /g) {    # Just remove the replacement chars, and warn (or Info?)
        Info('misdefined', $encoding, $self, "input isn't valid under encoding $encoding"); } } }
  $line .= "\r";                        # put line ending back!

  if (!($$self{lineno} % 25)) {
    NoteProgressDetailed("[#$$self{lineno}]"); }
  return $line; }

sub stringify {
  my ($self) = @_;
  return "FileMouth[$$self{source}\@$$self{lineno}x$$self{colno}]"; }

#**********************************************************************
# LaTeXML::StyleMixin
#    Mixin for Mouth's that serve as source for style/package/class/whatever
#**********************************************************************
# package LaTeXML::StyleMixin;
# use strict;
# use LaTeXML::Global;

# sub postInitialize {
#   my($self)=@_;
#   NoteBegin("Style $$self{source}");
#   $$self{saved_at_cc} = $STATE->lookupCatcode('@');
#   $$self{SAVED_INCLUDE_COMMENTS} = $STATE->lookupValue('INCLUDE_COMMENTS');
#   $STATE->assignCatcode('@'=>CC_LETTER);
#   $STATE->assignValue(INCLUDE_COMMENTS=>0);
#   $self;  }

# sub preFinish {
#   my($self)=@_;
#   $STATE->assignCatcode('@'=> $$self{saved_at_cc});
#   $STATE->assignValue(INCLUDE_COMMENTS=>$$self{SAVED_INCLUDE_COMMENTS});
#   NoteEnd("Style $$self{source}"); }

#**********************************************************************
# LaTeXML::StyleMouth
#    Read TeX Tokens from a style file.
#**********************************************************************

package LaTeXML::StyleMouth;
use strict;
use LaTeXML::Global;
use LaTeXML::Util::Pathname;
##use base qw(LaTeXML::FileMouth LaTeXML::StyleMixin);
use base qw(LaTeXML::FileMouth);

sub new {
  my ($class, $pathname) = @_;
##  my $self = bless {source=>pathname_relative($pathname,pathname_cwd)}, $class;
  my ($dir, $name, $ext) = pathname_split($pathname);
  my $self = bless { source => $pathname, shortsource => "$name.$ext" }, $class;
  $$self{fordefinitions} = 1;
  $$self{notes}          = 1;
  $self->openFile($pathname);
  $self->initialize;
  #  $self->postInitialize;
  return $self; }

# sub finish {
#   my($self)=@_;
#   $self->preFinish; $self->SUPER::finish; }
#**********************************************************************
# LaTeXML::StyleMouth
#    Read TeX Tokens from a style file.
#**********************************************************************

package LaTeXML::StyleStringMouth;
use strict;
use LaTeXML::Global;
#use base qw(LaTeXML::Mouth LaTeXML::StyleMixin);
use base qw(LaTeXML::Mouth);

sub new {
  my ($class, $pathname, $string) = @_;
##  my $self = bless {source=>$pathname}, $class;
  my ($dir, $name, $ext) = pathname_split($pathname);
  my $self = bless { source => $pathname, shortsource => "$name.$ext" }, $class;
  $$self{fordefinitions} = 1;
  $$self{notes}          = 1;
  $self->openString($string);
  $self->initialize;
  #  $self->postInitialize;
  return $self; }

# sub finish {
#   my($self)=@_;
#   $self->preFinish; $self->SUPER::finish; }

#**********************************************************************
package LaTeXML::Mouth::literal;
use base qw(LaTeXML::Mouth);

sub new {
  my ($class, $data, %options) = @_;
  $data =~ s/^literal://;
  my $self = bless { source => "Anonymous String", shortsource => "String" }, $class;
  $$self{fordefinitions} = 1 if $options{fordefinitions};
  $$self{notes}          = 1 if $options{notes};
  $self->openString($data);
  $self->initialize;
  return $self; }

#**********************************************************************
package LaTeXML::Mouth::cached;
use base qw(LaTeXML::Mouth);
use LaTeXML::Util::Pathname;

sub new {
  my ($class, $pathname, %options) = @_;
  #  my $self =  bless {source=>pathname_relative($pathname,pathname_cwd)}, $class;
  my ($dir, $name, $ext) = pathname_split($pathname);
  my $self = bless { source => $pathname, shortsource => "$name.$ext" }, $class;
  $$self{fordefinitions} = 1 if $options{fordefinitions};
  $$self{notes}          = 1 if $options{notes};
  $self->openString($options{content});
  $self->initialize;
  return $self; }

#**********************************************************************
package LaTeXML::Mouth::file;
use base qw(LaTeXML::FileMouth);
use LaTeXML::Util::Pathname;

sub new {
  my ($class, $pathname, %options) = @_;
  #  my $self =  bless {source=>pathname_relative($pathname,pathname_cwd)}, $class;
  my ($dir, $name, $ext) = pathname_split($pathname);
  my $self = bless { source => $pathname, shortsource => "$name.$ext" }, $class;
  $$self{fordefinitions} = 1 if $options{fordefinitions};
  $$self{notes}          = 1 if $options{notes};
  $self->openFile($pathname);
  $self->initialize;
  return $self; }

#**********************************************************************
package LaTeXML::Mouth::http;
use base qw(LaTeXML::Mouth);
use LaTeXML::Util::WWW;
use LaTeXML::Global;

sub new {
  my ($class,   $url,  %options) = @_;
  my ($urlbase, $name, $ext)     = url_split($url);
  $STATE->assignValue(URLBASE => $urlbase) if defined $urlbase;
  my $self = bless { source => $url, shortsource => $name }, $class;
  $$self{fordefinitions} = 1 if $options{fordefinitions};
  $$self{notes}          = 1 if $options{notes};
  my $content = auth_get($url);
  $self->openString($content);
  $self->initialize;
  return $self; }

#**********************************************************************
package LaTeXML::Mouth::https;
use base qw(LaTeXML::Mouth::http);

#**********************************************************************
# A fake mouth provides a hook for getting the Locator of anything
# defined in a perl module (*.pm, *.ltxml, *.latexml...)
package LaTeXML::PerlMouth;
use strict;
use LaTeXML::Global;
use LaTeXML::Util::Pathname;

sub new {
  my ($class, $pathname) = @_;
##  my $shortpath=pathname_relative($pathname,pathname_cwd);
##  my $self = bless {source=>(length($pathname) < length($shortpath) ? $pathname : $shortpath)},$class;
  my ($dir, $name, $ext) = pathname_split($pathname);
  my $self = bless { source => $pathname, shortsource => "$name.$ext" }, $class;
  NoteBegin("Loading $$self{source}");
  return $self; }

sub finish {
  my ($self) = @_;
  NoteEnd("Loading $$self{source}");
  return; }

# Evolve to figure out if this gets dynamic location!
sub getLocator {
  my ($self, $length) = @_;
  my $path  = $$self{source};
  my $loc   = ($length && $length < 0 ? $$self{shortsource} : $$self{source});
  my $frame = 2;
  my ($pkg, $file, $line);
  while (($pkg, $file, $line) = caller($frame++)) {
    last if $file eq $path; }
  return $loc . ($line ? " line $line" : ''); }

sub getSource {
  my ($self) = @_;
  return $$self{source}; }

sub hasMoreInput {
  return 0; }

sub readToken {
  return; }

sub stringify {
  my ($self) = @_;
  return "PerlMouth[$$self{source}]"; }

#**********************************************************************
1;

__END__

=pod 

=head1 NAME

C<LaTeXML::Mouth> - tokenize the input.

=head1 DESCRIPTION

A C<LaTeXML::Mouth> (and subclasses) is responsible for I<tokenizing>, ie.
converting plain text and strings into L<LaTeXML::Token>s according to the
current category codes (catcodes) stored in the C<LaTeXML::State>.

=over 4

=item C<LaTeXML::FileMouth>

=begin latex

\label{LaTeXML::FileMouth}

=end latex

specializes C<LaTeXML::Mouth> to tokenize from a file.

=item C<LaTeXML::StyleMouth>

=begin latex

\label{LaTeXML::StyleMouth}

=end latex

further specializes C<LaTeXML::FileMouth> for processing
style files, setting the catcode for C<@> and ignoring comments.

=item C<LaTeXML::PerlMouth>

=begin latex

\label{LaTeXML::PerlMouth}

=end latex

is not really a Mouth in the above sense, but is used
to definitions from perl modules with exensions C<.ltxml> and C<.latexml>.

=back

=head2 Creating Mouths

=over 4

=item C<< $mouth = LaTeXML::Mouth->new($string); >>

Creates a new Mouth reading from C<$string>.

=item C<< $mouth = LaTeXML::FileMouth->new($pathname); >>

Creates a new FileMouth to read from the given file.

=item C<< $mouth = LaTeXML::StyleMouth->new($pathname); >>

Creates a new StyleMouth to read from the given style file.

=back

=head2 Methods

=over 4

=item C<< $token = $mouth->readToken; >>

Returns the next L<LaTeXML::Token> from the source.

=item C<< $boole = $mouth->hasMoreInput; >>

Returns whether there is more data to read.

=item C<< $string = $mouth->getLocator($long); >>

Return a description of current position in the source, for reporting errors.

=item C<< $tokens = $mouth->readTokens($until); >>

Reads tokens until one matches C<$until> (comparing the character, but not catcode).
This is useful for the C<\verb> command.

=item C<< $lines = $mouth->readRawLine; >>

Reads a raw (untokenized) line from C<$mouth>, or undef if none is found.

=back

=head1 AUTHOR

Bruce Miller <bruce.miller@nist.gov>

=head1 COPYRIGHT

Public domain software, produced as part of work done by the
United States Government & not subject to copyright in the US.

=cut
