#--------------------------------------------------------------------
#----- GRNOC RabbitMQ 
#-----
#----- Copyright(C) 2015 The Trustees of Indiana University
#--------------------------------------------------------------------
#-----
#----- This is a base module for all of the other GRNOC RabbitMQ
#----- modules, the goal is to abstract away lots of the boiler plate
#----- RabbitMQ facilities to make it simpler for developers to use
#--------------------------------------------------------------------

package GRNOC::RabbitMQ;

use strict;
use warnings;

our $VERSION = '1.0.0';

sub new {
    my $caller = shift;

    my $class = ref( $caller );
    $class = $caller if ( !$class );

    my $self = {
        @_
    };

    bless( $self, $class );

    return $self;


sub get_version{
    my $self = shift;
    return $VERSION;
}

1;
