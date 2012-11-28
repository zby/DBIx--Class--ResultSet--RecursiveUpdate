use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t_dbic/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

# create a track with a 'cd_single' (might_have)
my $track_id;
lives_ok ( sub {
  my $cd = $schema->resultset('CD')->first;
  my $track = $schema->resultset('Track')->create ({
    cd => $cd,
    title => 'Multicreate rocks',
    cd_single => {
      artist => $cd->artist,
      year => 2008,
      title => 'Disemboweling MultiCreate',
      tracks => [
        { title => 'Why does mst write this way' },
        { title => 'Chainsaw celebration' },
        { title => 'Purl cleans up' },
      ],
    },
  });

  isa_ok ($track, 'DBICTest::Track', 'Main Track object created');
  $track_id = $track->id;
  is ($track->title, 'Multicreate rocks', 'Correct Track title');

  my $single = $track->cd_single;
  isa_ok ($single, 'DBICTest::CD', 'Created a single with the track');
});

my $track = $schema->resultset('Track')->find($track_id);
ok( $track );
my $old_cd_single = $track->get_column('cd_single');
my $updates = {
    trackid => $track_id,
    cd => $track->cd->cdid,
    title => 'Multicreate rocks',
    cd_single => {
        artist => $track->cd->artist,
        year => 2010,
        title => 'Replaced the Track',
    }
};
$track->recursive_updates($updates);
ok( $track->cd_single, 'we have a cd_single' );
ok( $old_cd_single != $track->get_column('cd_single'), 'we have a different cd_single' );

done_testing;
