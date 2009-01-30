# -*- perl -*-
package RunTests;
use Exporter 'import'; # gives you Exporter's import() method directly
@EXPORT = qw(run_tests);
use strict;
use Test::More; 

sub run_tests{
    my $schema = shift;
    
    my $dvd_rs = $schema->resultset( 'Dvd' );
    my $user_rs = $schema->resultset( 'User' );

    my $owner = $user_rs->next;
    my $another_owner = $user_rs->next;
    my $initial_user_count = $user_rs->count;
    my $initial_dvd_count = $dvd_rs->count;
   
    # creating new record linked to some old record
    
    my $updates;
    $updates = {
        id => undef,
            name => 'Test name 2',
            viewings => [ { user_id => $owner->id } ],
            owner => { id => $owner->id },
    };
    
    my $new_dvd = $dvd_rs->recursive_update( $updates );
#    my $new_dvd = $dvd_rs->create( $updates );
  
    ok ( $new_dvd->isa( 'DBSchema::Result::Dvd' ), 'Dvd created' );
    is ( $dvd_rs->count, $initial_dvd_count + 1, 'Dvd created' );
    is ( $schema->resultset( 'User' )->count, $initial_user_count, "No new user created" );
    is ( $new_dvd->name, 'Test name 2', 'Dvd name set' );
    is ( $new_dvd->owner->id, $owner->id, 'Owner set' );
    is ( $new_dvd->viewings->count, 1, 'Viewing created' );
;    
    # creating new records
    my $updates = {
        id => undef,
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
    # changing existing records
    
    my $num_of_users = $user_rs->count;
    $updates = {
            id => $dvd->id,
            aaaa => undef,
            name => 'Test name',
            tags => [ ], 
            'owner' => $another_owner->id,
            current_borrower => {
                username => 'new name a',
                name => 'new name a',
                password => 'new password a',
            }
    };
    $dvd = $dvd_rs->recursive_update( $updates );
    
    is ( $schema->resultset( 'User' )->count, $initial_user_count + 1, "No new user created" );
    is ( $dvd->name, 'Test name', 'Dvd name set' );
    is ( $dvd->owner->id, $another_owner->id, 'Owner updated' );
    is ( $dvd->current_borrower->name, 'new name a', 'Related record modified' );
    is ( $dvd->tags->count, 0, 'Tags deleted' );

    # repeatable
    
    $updates = {
        id => undef,
        name  => 'temp name',
        username => 'temp username',
        password => 'temp username',
        owned_dvds =>[
        {
            'id' => undef,
            'name' => 'temp name 1',
            'tags' => [ 1, 2 ],
        },
        {
            'id' => undef,
            'name' => 'temp name 2',
            'tags' => [ 2, 3 ],
        }
        ]
    };
    
    my $user = $user_rs->recursive_update( $updates );
    my %owned_dvds = map { $_->name => $_ } $user->owned_dvds;
    is( scalar keys %owned_dvds, 2, 'Has many relations created' );
    ok( $owned_dvds{'temp name 1'}, 'Name in a has_many related record saved' );
    my @tags = $owned_dvds{'temp name 1'}->tags;
    is( scalar @tags, 2, 'Tags in has_many related record saved' );
    ok( $owned_dvds{'temp name 2'}, 'Second name in a has_many related record saved' );

}    
