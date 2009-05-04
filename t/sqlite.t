# -*- perl -*-

use lib 't/lib';
use DBSchema;
use RunTests;
use Test::More;

#unlink 't/var/dvdzbr.db';
my $schema = DBSchema::get_test_schema();
run_tests( $schema );

