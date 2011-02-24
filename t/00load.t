use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('DBIx::Class::ResultSet::RecursiveUpdate');
}

diag(
    "Testing DBIx::Class::ResultSet::RecursiveUpdate $DBIx::Class::ResultSet::RecursiveUpdate::VERSION"
);

done_testing();
