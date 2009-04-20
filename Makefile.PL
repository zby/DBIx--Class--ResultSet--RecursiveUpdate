use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'DBIx::Class::ResultSet::RecursiveUpdate',
    AUTHOR              => 'Zbigniew Lukasiak <zby@cpan.org>',
    VERSION_FROM        => 'lib/DBIx/Class/ResultSet/RecursiveUpdate.pm',
    ABSTRACT_FROM       => 'lib/DBIx/Class/ResultSet/RecursiveUpdate.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'version'    => 0,
        'DBIx::Class' => '0.08100',
        'DBIx::Class::IntrospectableM2M' => 0,
        'SQL::Translator' => '0.08',
        'DateTime'   => 0,
        'DBD::SQLite' => '1.21',
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'DBIx-Class-ResultSet-RecursiveUpdate-*' },
    LICENSE             => 'perl'
);

