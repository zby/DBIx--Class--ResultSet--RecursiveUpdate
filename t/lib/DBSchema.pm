package DBSchema;

# Created by DBIx::Class::Schema::Loader v0.03000 @ 2006-10-02 08:24:09

use strict;
use warnings;

use base 'DBIx::Class::Schema';
use DateTime;

__PACKAGE__->load_namespaces( default_resultset_class => '+DBIx::Class::ResultSet::RecursiveUpdate' );

sub tables_exist {
    my ( $dsn, $user, $pass ) = @_;
    my $dbh = DBI->connect($dsn, $user, $pass, );
    return $dbh->tables( '%', '%', 'dvd', );
}


sub get_test_schema {
    my ( $dsn, $user, $pass ) = @_;
    $dsn ||= 'dbi:SQLite:dbname=t/var/dvdzbr.db';
    warn "testing $dsn\n";
    my $schema = __PACKAGE__->connect( $dsn, $user, $pass, {} );
    my $deploy_attrs;
    $deploy_attrs->{add_drop_table} = 1 if tables_exist( $dsn, $user, $pass );
    $schema->deploy( $deploy_attrs );
    $schema->populate('Personality', [
        [ qw/user_id / ],
        [ '1'],
        [ '2' ],
        [ '3'],
        ]
    );
    $schema->populate('User', [
        [ qw/username name password / ],
        [ 'jgda', 'Jonas Alves', ''],
        [ 'isa' , 'Isa', '', ],
        [ 'zby' , 'Zbyszek Lukasiak', ''],
        ]
    );
    $schema->populate('Tag', [
        [ qw/name file / ],
        [ 'comedy', '' ],
        [ 'dramat', '' ],
        [ 'australian', '' ],
        ]
    );
    $schema->populate('Dvd', [
        [ qw/name imdb_id owner current_borrower creation_date alter_date / ],
        [ 'Picnick under the Hanging Rock', 123, 1, 3, '2003-01-16 23:12:01', undef ],
        [ 'The Deerhunter', 1234, 1, 1, undef, undef ],
        [ 'Rejs', 1235, 3, 1, undef, undef ],
        [ 'Seksmisja', 1236, 3, 1, undef, undef ],
        ]
    ); 
    $schema->populate( 'Dvdtag', [
        [ qw/ dvd tag / ],
        [ 1, 2 ],
        [ 1, 3 ],
        [ 3, 1 ],
        [ 4, 1 ],
        ]
    );
    return $schema;
}
    
    
1;

