package DBIx::Class::ResultSet::RecursiveUpdate;

use version; $VERSION = qv('0.001');

use warnings;
use strict;
use Carp;

use base qw(DBIx::Class::ResultSet);

sub recursive_update { 
    my( $self, $updates ) = @_;
    my $object;
    $object = $self->find( $updates, { key => 'primary' } ) || $self->new( {} );

    for my $name ( keys %$updates ){ 
        if($object->can($name)){
            my $value = $updates->{$name};

            # updating relations that that should be done before the row is inserted into the database
            # like belongs_to
            if( $object->result_source->has_relationship($name) 
                    and 
                ref $value
            ){
                my $info = $object->result_source->relationship_info( $name );
                if( $info and not $info->{attrs}{accessor} eq 'multi'
                        and 
                    _master_relation_cond( $object, $info->{cond}, $self->_get_pk_for_related( $name ) )
                ){
                    my $related_result = $object->related_resultset( $name );
                    my $sub_object = $related_result->recursive_update( $value );
                    $object->set_from_related( $name, $sub_object );
                }
            }
            # columns and other accessors
            elsif( $object->result_source->has_column($name) 
                    or 
                !$object->can( 'set_' . $name ) 
            ) {
                $object->$name($value);
            }
        }
        #warn Dumper($object->{_column_data}); use Data::Dumper;
    }
    _delete_empty_auto_increment($object);
    $object->update_or_insert;

    # updating relations that can be done only after the row is inserted into the database
    # like has_many and many_to_many
    for my $name ( keys %$updates ){
        my $value = $updates->{$name};
        # many to many case
        if( $self->is_m2m( $name ) ) {
                my ( $pk ) = $self->_get_pk_for_related( $name );
                my @values = @{$updates->{$name}};
                my @rows;
                my $result_source = $object->$name->result_source;
                @rows = $result_source->resultset->search({ $pk => [ @values ] } ) if @values; 
                my $set_meth = 'set_' . $name;
                $object->$set_meth( \@rows );
        }
        elsif( $object->result_source->has_relationship($name) ){
            my $info = $object->result_source->relationship_info( $name );
            # has many case
            if( ref $updates->{$name} eq 'ARRAY' ){
                for my $sub_updates ( @{$updates->{$name}} ) {
                    my $sub_object = $object->search_related( $name )->recursive_update( $sub_updates );
                }
            }
            # might_have and has_one case
            elsif ( ! _master_relation_cond( $object, $info->{cond}, $self->_get_pk_for_related( $name ) ) ){
                my $sub_object = $object->search_related( $name )->recursive_update( $value );
                #$object->set_from_related( $name, $sub_object );
            }
        }
    }
    return $object;
}

sub is_m2m {
    my( $self, $relation ) = @_;
    my $object = $self->new({});
    if ( $object->can($relation) and 
        !$object->result_source->has_relationship($relation) and 
        $object->can( 'set_' . $relation)
    ){
        return 1;
    }
    return;
}

sub get_m2m_source {
    my( $self, $relation ) = @_;
    my $object = $self->new({});
    my $r = $object->$relation;
    return $r->result_source;
}

 
sub _delete_empty_auto_increment {
    my ( $object ) = @_;
    for my $col ( keys %{$object->{_column_data}}){
        if( $object->result_source->column_info( $col )->{is_auto_increment} 
                and 
            ( ! defined $object->{_column_data}{$col} or $object->{_column_data}{$col} eq '' )
        ){
            delete $object->{_column_data}{$col}
        }
    }
}

sub _get_pk_for_related {
    my ( $self, $relation ) = @_;

    my $result_source;
    if( $self->result_source->has_relationship( $relation ) ){
        $result_source = $self->result_source->related_source( $relation );
    }
    # many to many case
    if ( $self->is_m2m( $relation ) ) {
        $result_source = $self->get_m2m_source( $relation );
    }
    return $result_source->primary_columns;
}

sub _master_relation_cond {
    my ( $object, $cond, @foreign_ids ) = @_;
    my $foreign_ids_re = join '|', @foreign_ids;
    if ( ref $cond eq 'HASH' ){
        for my $f_key ( keys %{$cond} ) {
            # might_have is not master
            my $col = $cond->{$f_key};
            $col =~ s/self\.//;
            if( $object->column_info( $col )->{is_auto_increment} ){
                return 0;
            }
            if( $f_key =~ /^foreign\.$foreign_ids_re/ ){
                return 1;
            }
        }
    }elsif ( ref $cond eq 'ARRAY' ){
        for my $new_cond ( @$cond ) {
            return 1 if _master_relation_cond( $object, $new_cond, @foreign_ids );
        }
    }
    return;
}

# Module implementation here


1; # Magic true value required at end of module
__END__

=head1 NAME

DBIx::Class::ResultSet::RecursiveUpdate - like update_or_create - but recursive 


=head1 VERSION

This document describes DBIx::Class::ResultSet::RecursiveUpdate version 0.0.1


=head1 SYNOPSIS

    __PACKAGE__->load_namespaces( default_resultset_class => '+DBIx::Class::ResultSet::RecursiveUpdate' );

in the Schema file (see t/lib/DBSchema.pm).  Or appriopriate 'use base' in the ResultSet classes. 

Then:

    my $user = $user_rs->recursive_update( { 
        id => 1, 
        owned_dvds => [ 
        { 
          id => undef, 
          title => 'One Flew Over the Cuckoo's Nest' 
        } 
        ] 
      }
    );

  
=head1 DESCRIPTION

    You can feed the ->create method with a recursive datastructure and have the related records
    created.  Unfortunately you cannot do a similar thing with update_or_create - this module
    tries to fill that void. 

    It is a base class for ResultSets providing just one method: recursive_update
    which works just like update_or_create but can recursively update or create
    data objects composed of multiple rows. All rows need to be identified by primary keys
    - so you need to provide them in the update structure (unless they can be deduced from 
    the parent row - for example when you have a belongs_to relationship).  
    When creating new rows in a table with auto_increment primary keys you need to 
    put 'undef' for the key value - this is then removed
    and a correct INSERT statement is generated.  

    For a many_to_many (pseudo) relation you can supply a list of primary keys
    from the other table - and it will link the record at hand to those and
    only those records identified by them.  This is convenient for handling web
    forms with check boxes (or a SELECT box with multiple choice) that let you
    update such (pseudo) relations.

    For a description how to set up base classes for ResultSets see load_namespaces
    in DBIx::Class::Schema.

    The support for many to many pseudo relationships should be treated as prototype -
    the DBIC author disagrees with the way I did it.


=head1 INTERFACE 

=head1 METHODS

=head2 recursive_update

The method that does the work here.

=head2 is_m2m

$self->is_m2m( 'name ' ) - answers the question if 'name' is a many to many
(pseudo) relation on $self.

=head2 get_m2m_source

$self->get_m2m_source( 'name' ) - returns the ResultSource linked to by the many
to many (pseudo) relation 'name' from $self.


=head1 DIAGNOSTICS


=head1 CONFIGURATION AND ENVIRONMENT

DBIx::Class::RecursiveUpdate requires no configuration files or environment variables.

=head1 DEPENDENCIES

    DBIx::Class

=head1 INCOMPATIBILITIES

=for author to fill in:

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-dbix-class-recursiveput@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Zbigniew Lukasiak  C<< <zby@cpan.org> >>
Influenced by code by Pedro Melo.

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2008, Zbigniew Lukasiak C<< <zby@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
