package # hide from PAUSE
    DBICTest::RunMode;

use strict;
use warnings;

BEGIN {
  if ($INC{'DBIx/Class.pm'}) {
    my ($fr, @frame) = 1;
    while (@frame = caller($fr++)) {
      last if $frame[1] !~ m|^t/lib/DBICTest|;
    }

    die __PACKAGE__ . " must be loaded before DBIx::Class (or modules using DBIx::Class) at $frame[1] line $frame[2]\n";
  }
}

use Path::Class qw/file dir/;
use File::Spec;

_check_author_makefile() unless $ENV{DBICTEST_NO_MAKEFILE_VERIFICATION};

# PathTools has a bug where on MSWin32 it will often return / as a tmpdir.
# This is *really* stupid and the result of having our lockfiles all over
# the place is also rather obnoxious. So we use our own heuristics instead
# https://rt.cpan.org/Ticket/Display.html?id=76663
my $tmpdir;
sub tmpdir {
  dir ($tmpdir ||= do {

    my $dir = dir(File::Spec->tmpdir);

    my @parts = File::Spec->splitdir($dir);
    if (@parts == 2 and $parts[1] eq '') {
      # This means we were give the root dir (C:\ or something equally unacceptable)
      # Replace with our local project tmpdir. This will make multiple runs
      # from different runs conflict with each other, but is much better than
      # polluting the root dir with random crap
      $dir = _find_co_root()->subdir('t')->subdir('var');
      $dir->mkpath;
    }

    $dir->stringify;
  });
}


# Die if the author did not update his makefile
#
# This is pretty heavy handed, so the check is pretty solid:
#
# 1) Assume that this particular module is loaded from -I <$root>/t/lib
# 2) Make sure <$root>/Makefile.PL exists
# 3) Make sure we can stat() <$root>/Makefile.PL
#
# If all of the above is satisfied
#
# *) die if <$root>/inc does not exist
# *) die if no stat() results for <$root>/Makefile (covers no Makefile)
# *) die if Makefile.PL mtime > Makefile mtime
#
sub _check_author_makefile {

  my $root = _find_co_root()
    or return;

  my $optdeps = file('lib/DBIx/Class/Optional/Dependencies.pm');

  # not using file->stat as it invokes File::stat which in turn breaks stat(_)
  my ($mf_pl_mtime, $mf_mtime, $optdeps_mtime) = ( map
    { (stat ($root->file ($_)) )[9] || undef }  # stat returns () on nonexistent files
    (qw|Makefile.PL  Makefile|, $optdeps)
  );

  return unless $mf_pl_mtime;   # something went wrong during co_root detection ?

  my @fail_reasons;

  if(not -d $root->subdir ('inc')) {
    push @fail_reasons, "Missing ./inc directory";
  }

  if(not $mf_mtime) {
    push @fail_reasons, "Missing ./Makefile";
  }
  else {
    if($mf_mtime < $mf_pl_mtime) {
      push @fail_reasons, "./Makefile.PL is newer than ./Makefile";
    }
    if($mf_mtime < $optdeps_mtime) {
      push @fail_reasons, "./$optdeps is newer than ./Makefile";
    }
  }

  if (@fail_reasons) {
    print STDERR <<'EOE';


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
======================== FATAL ERROR ===========================
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

We have a number of reasons to believe that this is a development
checkout and that you, the user, did not run `perl Makefile.PL`
before using this code. You absolutely _must_ perform this step,
to ensure you have all required dependencies present. Not doing
so often results in a lot of wasted time for other contributors
trying to assit you with spurious "its broken!" problems.

By default DBICs Makefile.PL turns all optional dependenciess into
*HARD REQUIREMENTS*, in order to make sure that the entire test
suite is executed, and no tests are skipped due to missing modules.
If you for some reason need to disable this behavior - supply the
--skip_author_deps option when running perl Makefile.PL

If you are seeing this message unexpectedly (i.e. you are in fact
attempting a regular installation be it through CPAN or manually),
please report the situation to either the mailing list or to the
irc channel as described in

http://search.cpan.org/dist/DBIx-Class/lib/DBIx/Class.pm#GETTING_HELP/SUPPORT

The DBIC team


Reasons you received this message:

EOE

    foreach my $r (@fail_reasons) {
      print STDERR "  * $r\n";
    }
    print STDERR "\n\n\n";

    exit 1;
  }
}

# Mimic $Module::Install::AUTHOR
sub is_author {

  my $root = _find_co_root()
    or return undef;

  return (
    ( not -d $root->subdir ('inc') )
      or
    ( -e $root->subdir ('inc')->subdir ($^O eq 'VMS' ? '_author' : '.author') )
  );
}

sub is_smoker {
  return ( $ENV{AUTOMATED_TESTING} && ! $ENV{PERL5_CPANM_IS_RUNNING} && ! $ENV{RELEASE_TESTING} )
}

sub is_plain {
  return (! __PACKAGE__->is_smoker && ! __PACKAGE__->is_author && ! $ENV{RELEASE_TESTING} )
}

# Try to determine the root of a checkout/untar if possible
# or return undef
sub _find_co_root {

    my @mod_parts = split /::/, (__PACKAGE__ . '.pm');
    my $rel_path = join ('/', @mod_parts);  # %INC stores paths with / regardless of OS

    return undef unless ($INC{$rel_path});

    # a bit convoluted, but what we do here essentially is:
    #  - get the file name of this particular module
    #  - do 'cd ..' as many times as necessary to get to t/lib/../..

    my $root = dir ($INC{$rel_path});
    for (1 .. @mod_parts + 2) {
        $root = $root->parent;
    }

    return (-f $root->file ('Makefile.PL') )
      ? $root
      : undef
    ;
}

1;
