# -*- perl -*-
package RunTests;
use Exporter 'import'; # gives you Exporter's import() method directly
@EXPORT = qw(run_tests);
use strict;
use Test::More; 


sub run_tests{
    my $schema = shift;
    
    my $dvd_rs = $schema->resultset( 'Dvd' );
    my $owner = $schema->resultset( 'User' )->first;
    my $initial_user_count = $schema->resultset( 'User' )->count;
   
    # creating new records
    
    my $updates = {
            id => undef,
            aaaa => undef,
            tags => [ '2', { id => '3' } ], 
            name => 'Test name',
    #        'creation_date.year' => 2002,
    #        'creation_date.month' => 1,
    #        'creation_date.day' => 3,
    #        'creation_date.hour' => 4,
    #        'creation_date.minute' => 33,
    #        'creation_date.pm' => 1,
            owner => $owner->id,
            current_borrower => {
                name => 'temp name',
                username => 'temp name',
                password => 'temp name',
            },
            liner_notes => {
                
                notes => 'test note',
            }
    };
    
    my $dvd = $dvd_rs->recursive_update( $updates );
   
    is ( $schema->resultset( 'User' )->count, $initial_user_count + 1, "One new user created" );
    is ( $dvd->name, 'Test name', 'Dvd name set' );
    is_deeply ( [ map {$_->id} $dvd->tags ], [ '2', '3' ], 'Tags set' );
    #my $value = $dvd->creation_date;
    #is( "$value", '2002-01-03T16:33:00', 'Date set');
    is ( $dvd->owner->id, $owner->id, 'Owner set' );
    
    is ( $dvd->current_borrower->name, 'temp name', 'Related record created' );
    is ( $dvd->liner_notes->notes, 'test note', 'might_have record created' );
    
    # changing existing records
    
    $updates = {
            id => $dvd->id,
            aaaa => undef,
            name => 'Test name',
            tags => [ ], 
            'owner' => $owner->id,
            current_borrower => {
                username => 'new name a',
                name => 'new name a',
                password => 'new password a',
            }
    };
    $dvd = $dvd_rs->recursive_update( $updates );
    
    is ( $schema->resultset( 'User' )->count, $initial_user_count + 1, "No new user created" );
    is ( $dvd->name, 'Test name', 'Dvd name set' );
    is ( $dvd->owner->id, $owner->id, 'Owner set' );
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
    
    my $user_rs = $schema->resultset( 'User' );
    my $user = $user_rs->recursive_update( $updates );
    my %owned_dvds = map { $_->name => $_ } $user->owned_dvds;
    is( scalar keys %owned_dvds, 2, 'Has many relations created' );
    ok( $owned_dvds{'temp name 1'}, 'Name in a has_many related record saved' );
    my @tags = $owned_dvds{'temp name 1'}->tags;
    is( scalar @tags, 2, 'Tags in has_many related record saved' );
    ok( $owned_dvds{'temp name 2'}, 'Second name in a has_many related record saved' );
}    
