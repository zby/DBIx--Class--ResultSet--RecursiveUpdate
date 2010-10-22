# -*- perl -*-
package RunTests;
use Exporter 'import';    # gives you Exporter's import() method directly
@EXPORT = qw(run_tests);
use strict;
use Test::More;
use DBIx::Class::ResultSet::RecursiveUpdate;

sub run_tests {
    my $schema = shift;

    plan tests => 47;

    my $dvd_rs  = $schema->resultset('Dvd');
    my $user_rs = $schema->resultset('User');

    my $owner              = $user_rs->next;
    my $another_owner      = $user_rs->next;
    my $initial_user_count = $user_rs->count;
    my $initial_dvd_count  = $dvd_rs->count;
    my $updates;

    $dvd_rs->search( { dvd_id => 1 } )->recursive_update( { 
            owner =>  { username => 'aaa'  } 
        },
        [ 'dvd_id' ]
    );

    my $u = $user_rs->find( $dvd_rs->find( 1 )->owner->id );
    is( $u->username, 'aaa', 'fixed_fields' );

    # try to create with a not existing rel
    $updates = {
        name        => 'Test name for nonexisting rel',
        username    => 'nonexisting_rel',
        password    => 'whatever',
        nonexisting => { foo => 'bar' },
    };
    eval { my $nonexisting_user = $user_rs->recursive_update($updates); };
    like(
        $@,
        qr/No such column, relationship, many-to-many helper accessor or generic accessor 'nonexisting'/,
        'nonexisting column, accessor, relationship fails'
    );

    # creating new record linked to some old record
    $updates = {
        name     => 'Test name 2',
        viewings => [ { user_id => $owner->id } ],
        owner => { id => $another_owner->id },
    };

    my $new_dvd = $dvd_rs->recursive_update($updates);

    is( $dvd_rs->count, $initial_dvd_count + 1, 'Dvd created' );
    is( $schema->resultset('User')->count,
        $initial_user_count, "No new user created" );
    is( $new_dvd->name,            'Test name 2',      'Dvd name set' );
    is( $new_dvd->owner->id,       $another_owner->id, 'Owner set' );
    is( $new_dvd->viewings->count, 1,                  'Viewing created' );

    # creating new records
    $updates = {

        #aaaa => undef,
        tags             => [ '2', { id => '3' } ],
        name             => 'Test name',
        owner            => $owner,
        current_borrower => {
            name     => 'temp name',
            username => 'temp name',
            password => 'temp name',
        },
        liner_notes => { notes => 'test note', },
        like_has_many  => [ { key2 => 1 } ],
        like_has_many2 => [
            {   onekey => { name => 'aaaaa' },
                key2   => 1
            }
        ],
    };

    my $dvd = $dvd_rs->recursive_update($updates);

    is( $dvd_rs->count, $initial_dvd_count + 2, 'Dvd created' );
    is( $schema->resultset('User')->count,
        $initial_user_count + 1,
        "One new user created"
    );
    is( $dvd->name, 'Test name', 'Dvd name set' );
    is_deeply( [ map { $_->id } $dvd->tags ], [ '2', '3' ], 'Tags set' );
    is( $dvd->owner->id, $owner->id, 'Owner set' );

    is( $dvd->current_borrower->name, 'temp name', 'Related record created' );
    is( $dvd->liner_notes->notes, 'test note', 'might_have record created' );
    ok( $schema->resultset('Twokeys')
            ->find( { dvd_name => 'Test name', key2 => 1 } ),
        'Twokeys created'
    );
    my $onekey =
        $schema->resultset('Onekey')->search( name => 'aaaaa' )->first;
    ok( $onekey, 'Onekey created' );
    ok( $schema->resultset('Twokeys_belongsto')
            ->find( { key1 => $onekey->id, key2 => 1 } ),
        'Twokeys_belongsto created'
    );
    TODO: {
        local $TODO = 'value of fk from a multi relationship';
        is( $dvd->twokeysfk, $onekey->id, 'twokeysfk in Dvd' );
    };
    is( $dvd->name, 'Test name', 'Dvd name set' );

    # changing existing records
    my $num_of_users = $user_rs->count;
    $updates = {
        id               => $dvd->dvd_id,         # id instead of dvd_id
                                                  #aaaa => undef,
        name             => undef,
        tags             => [],
        'owner'          => $another_owner->id,
        current_borrower => {
            username => 'new name a',
            name     => 'new name a',
            password => 'new password a',
        },
        liner_notes => { notes => 'test note changed', },

    };
    my $dvd_updated = $dvd_rs->recursive_update($updates);

    is( $dvd_updated->dvd_id, $dvd->dvd_id, 'Pk from "id"' );
    is( $schema->resultset('User')->count,
        $initial_user_count + 1,
        "No new user created"
    );
    is( $dvd_updated->name, undef, 'Dvd name deleted' );
    is( $dvd_updated->owner->id, $another_owner->id, 'Owner updated' );
    is( $dvd_updated->current_borrower->name,
        'new name a', 'Related record modified' );
    is( $dvd_updated->tags->count, 0, 'Tags deleted' );
    is( $dvd_updated->liner_notes->notes,
        'test note changed',
        'might_have record changed'
    );

    $new_dvd->update( { name => 'New Test Name' } );
    $updates = {
        id => $new_dvd->dvd_id,    # id instead of dvd_id
        like_has_many => [ { dvd_name => $dvd->name, key2 => 1 } ],
    };
    $dvd_updated = $dvd_rs->recursive_update($updates);
    ok( $schema->resultset('Twokeys')
            ->find( { dvd_name => 'New Test Name', key2 => 1 } ),
        'Twokeys updated'
    );
    ok( !$schema->resultset('Twokeys')
            ->find( { dvd_name => $dvd->name, key2 => 1 } ),
        'Twokeys updated'
    );

    # repeatable
    $updates = {
        name       => 'temp name',
        username   => 'temp username',
        password   => 'temp username',
        owned_dvds => [
            {   'name' => 'temp name 1',
                'tags' => [ 1, 2 ],
            },
            {   'name' => 'temp name 2',
                'tags' => [ 2, 3 ],
            }
        ]
    };

    my $user = $user_rs->recursive_update($updates);
    is( $schema->resultset('User')->count,
        $initial_user_count + 2,
        "New user created"
    );
    is( $dvd_rs->count, $initial_dvd_count + 4, 'Dvds created' );
    my %owned_dvds = map { $_->name => $_ } $user->owned_dvds;
    is( scalar keys %owned_dvds, 2, 'Has many relations created' );
    ok( $owned_dvds{'temp name 1'},
        'Name in a has_many related record saved' );
    my @tags = $owned_dvds{'temp name 1'}->tags;
    is( scalar @tags, 2, 'Tags in has_many related record saved' );
    ok( $owned_dvds{'temp name 2'},
        'Second name in a has_many related record saved' );

    # update has_many where foreign cols aren't nullable
    $updates = {
        id      => $user->id,
        address => {
            street => "101 Main Street",
            city   => "Podunk",
            state  => "New York"
        },
        owned_dvds => [ { id => 1, }, ]
    };
    $user = $user_rs->recursive_update($updates);
    is( $schema->resultset('Address')->search( { user_id => $user->id } )
            ->count,
        1,
        'the right number of addresses'
    );
    $dvd = $dvd_rs->find(1);
    is( $dvd->get_column('owner'), $user->id, 'foreign key set' );

    $dvd_rs->update( { current_borrower => $user->id } );
    ok( $user->borrowed_dvds->count > 1, 'Precond' );
    $updates = {
        id            => $user->id,
        borrowed_dvds => [ { id => $dvd->id }, ]
    };
    $user =
        DBIx::Class::ResultSet::RecursiveUpdate::Functions::recursive_update(
        resultset        => $user_rs,
        updates          => $updates,
        if_not_submitted => 'set_to_null',
        );
    is( $user->borrowed_dvds->count, 1, 'set_to_null' );

    # has_many where foreign cols are nullable
    $dvd_rs->update( { current_borrower => $user->id } );
    $updates = {
        id            => $user->id,
        borrowed_dvds => [ { id => $dvd->id }, ]
    };
    $user =
        DBIx::Class::ResultSet::RecursiveUpdate::Functions::recursive_update(
        resultset        => $user_rs,
        updates          => $updates,
        if_not_submitted => 'delete',
        );
    is( $user->borrowed_dvds->count, 1, 'if_not_submitted delete' );

    @tags = $schema->resultset('Tag')->search();
    $dvd_updated =
        DBIx::Class::ResultSet::RecursiveUpdate::Functions::recursive_update(
        resultset => $schema->resultset('Dvd'),
        updates   => {
            id   => $dvd->dvd_id,    # id instead of dvd_id
            tags => [
                { id => $tags[0]->id, file => 'file0' },
                { id => $tags[1]->id, file => 'file1' }
            ],
        }
        );
    $tags[$_]->discard_changes for 0 .. 1;
    is( $tags[0]->file, 'file0', 'file set in tag' );
    is( $tags[1]->file, 'file1', 'file set in tag' );
    my @rel_tags = $dvd_updated->tags;
    is( scalar @rel_tags, 2, 'tags related' );
    ok( $rel_tags[0]->file eq 'file0' || $rel_tags[0]->file eq 'file1',
        'tags related' );

    my $new_person = {
        name     => 'Amiri Barksdale',
        username => 'amiri',
        password => 'amiri',
    };
    ok( my $new_user = $user_rs->recursive_update($new_person) );

    # delete has_many where foreign cols aren't nullable
    my $rs_user_dvd = $user->owned_dvds;
    my @user_dvd_ids = map { $_->id } $rs_user_dvd->all;
    is( $rs_user_dvd->count, 1, 'user owns 1 dvd');
    $updates = {
        id         => $user->id,
        owned_dvds => undef,
    };
    $user = $user_rs->recursive_update($updates);
    is( $user->owned_dvds->count, 0, 'user owns no dvds');
    is( $dvd_rs->search({ dvd_id => {-in => \@user_dvd_ids }})->count, 0, 'owned dvds deleted' );

#    $updates = {
#            name => 'Test name 1',
#    };
#    $dvd = $dvd_rs->search( { id => $dvd->id } )->recursive_update( $updates, [ 'id' ] );
#    is ( $dvd->name, 'Test name 1', 'Dvd name set in a resultset with restricted id' );
}
