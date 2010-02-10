use strict;
use warnings;
use Test::More;


my $schema = DBICTest->init_schema();

my $dvd_rs = $schema->resultset( 'Dvd' );
my $user_rs = $schema->resultset( 'User' );

my $owner = $user_rs->next;
my $another_owner = $user_rs->next;
my $initial_user_count = $user_rs->count;
my $initial_dvd_count = $dvd_rs->count;
my $updates;

# creating new record linked to some old record
$updates = {
        name => 'Test name 2',
        viewings => [ { user_id => $owner->id } ],
        owner => { id => $another_owner->id },
};

my $new_dvd = $dvd_rs->recursive_update( $updates );
#    my $new_dvd = $dvd_rs->create( $updates );

is ( $dvd_rs->count, $initial_dvd_count + 1, 'Dvd created' );
is ( $schema->resultset( 'User' )->count, $initial_user_count, "No new user created" );
is ( $new_dvd->name, 'Test name 2', 'Dvd name set' );
is ( $new_dvd->owner->id, $another_owner->id, 'Owner set' );
is ( $new_dvd->viewings->count, 1, 'Viewing created' );

# creating new records
$updates = {
        aaaa => undef,
        tags => [ '2', { id => '3' } ], 
        name => 'Test name',
        owner => $owner,
        current_borrower => {
            name => 'temp name',
            username => 'temp name',
            password => 'temp name',
        },
        liner_notes => {
            notes => 'test note',
        },
        like_has_many => [
        { key2 => 1 }
        ],
        like_has_many2 => [ 
            {
                onekey => { name => 'aaaaa' },
                key2 => 1
            }
        ],
};

my $dvd = $dvd_rs->recursive_update( $updates );
;   
is ( $dvd_rs->count, $initial_dvd_count + 2, 'Dvd created' );
is ( $schema->resultset( 'User' )->count, $initial_user_count + 1, "One new user created" );
is ( $dvd->name, 'Test name', 'Dvd name set' );
is_deeply ( [ map {$_->id} $dvd->tags ], [ '2', '3' ], 'Tags set' );
is ( $dvd->owner->id, $owner->id, 'Owner set' );

is ( $dvd->current_borrower->name, 'temp name', 'Related record created' );
is ( $dvd->liner_notes->notes, 'test note', 'might_have record created' );
ok ( $schema->resultset( 'Twokeys' )->find( { dvd_name => 'Test name', key2 => 1 } ), 'Twokeys created' );
my $onekey = $schema->resultset( 'Onekey' )->search( name => 'aaaaa' )->first;
ok ( $onekey, 'Onekey created' );
ok ( $schema->resultset( 'Twokeys_belongsto' )->find( { key1 => $onekey->id, key2 => 1 } ), 'Twokeys created' );

is ( $dvd->name, 'Test name', 'Dvd name set' );

done_testing;
