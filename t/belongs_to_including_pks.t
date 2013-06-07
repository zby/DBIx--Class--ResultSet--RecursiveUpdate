use strict;
use warnings;
use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

diag
    'Update foreign key with an updated primary key (similar to "Create foreign key col obj including PK" in 96multi_create.t)';
eval {
    my $new_cd_hashref = {
        cdid   => 30,
        title  => 'Boogie Woogie',
        year   => '2007',
        artist => { artistid => 1 }
    };

    my $cd = $schema->resultset("CD")->find(1);
    is( $cd->artist->id, 1, 'rel okay' );

    my $new_cd = $schema->resultset("CD")->recursive_update($new_cd_hashref);
    is( $new_cd->artist->id, 1, 'new id retained okay' );
};

eval {
    my $updated_cd = $schema->resultset("CD")->recursive_update(
        {   cdid   => 30,
            title  => 'Boogie Wiggle',
            year   => '2007',
            artist => { artistid => 2 }
        }
    );
    is( $updated_cd->artist->id, 2, 'related artist changed correctly' );
};
is( $@, '', 'new cd created without clash on related artist' );

done_testing;

# vim: set ft=perl ts=4 expandtab:
