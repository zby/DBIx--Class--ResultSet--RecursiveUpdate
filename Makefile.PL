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
        'DBIx::Class' => '0.08011',
        'DBIx::Class::IntrospectableM2M' => 0,
        'SQL::Translator' => '0.08',
        'Date::Time'  => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'DBIx-Class-ResultSet-RecursiveUpdate-*' },
);
