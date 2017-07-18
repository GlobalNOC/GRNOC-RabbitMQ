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

=head1 NAME
GRNOC::RabbitMQ - GRNOC RabbitMQ Library for perl
=head1 SYNOPSIS
    use GRNOC::RabbitMQ;
print "This is version $GRNOC::RabbitMQ::VERSION\n";
=head1 DESCRIPTION
The RabbitMQ collection is a set of perl modules which are used to
provide and interact with GRNOC AMQP services

The main features of the library are:
=over
=item *
Provides easy to use interface for implementing services and service
clients that work with our systems
=item *
Provides an object oriented model for communcation with services
=item *
Consistent base for all services, using proper POD documetation, named
parameters and OO where sensible.
=back
=head1 OVERVIEW OF CLASSES AND PACKAGES
This table should give you a quick overview of the classes provided by the
library. Indentation shows class inheritance.
  GRNOC::RabbitMQ::Method      -- RabbitMQ Method handler object
  GRNOC::RabbitMQ::Dispatcher  -- RabbitMQ Dispatcher object
  GRNOC::RabbitMQ::Client      -- RabbitMQ Client ojbect interface
=head1 AUTHOR
GRNOC System Engineering, C<< <syseng at grnoc.iu.edu> >>
=head1 BUGS
Please report any bugs or feature requests via grnoc bugzilla
=head1 SUPPORT
You can find documentation for this module with the perldoc command.
    perldoc GRNOC::RabbitMQ
=cut

use strict;
use warnings;

use AnyEvent::RabbitMQ;

our $VERSION = '1.1.1';


=head2 connect_to_rabbit

=cut
sub connect_to_rabbit{
    my %args = ( host => 'localhost',
		 port => 5672,
		 user => 'guest',
		 pass => 'guest',
		 vhost => '/',
		 timeout => 10,
		 on_success => \&GRNOC::RabbitMQ::channel_creator,
		 on_failure => \&GRNOC::RabbitMQ::on_failure_handler,
		 on_read_failure => \&GRNOC::RabbitMQ::on_failure_handler,
		 on_return => \&GRNOC::RabbitMQ::on_failure_handler,
		 on_close => \&GRNOC::RabbitMQ::on_close_handler,
		 exchange => undef,
		 obj => undef,
		 queue => undef,
		 exclusive => 0,
		 type => undef,
		 @_);

    my $cv = AnyEvent->condvar;

    my $ar = AnyEvent::RabbitMQ->new->load_xml_spec()->connect(
        host => $args{'host'},
        port => $args{'port'},
        user => $args{'user'},
        pass => $args{'pass'},
        vhost => $args{'vhost'},
        timeout => $args{'timeout'},
        tls => 0,
        on_success => $args{'on_success'}(cv => $cv, obj => $args{'obj'}, queue => $args{'queue'}, exclusive => $args{'exclusive'}, type => $args{'type'}, exchange => $args{'exchange'}),
        on_failure => $args{'on_failure'}(cv => $cv, obj => $args{'obj'}),
        on_read_failure => $args{'on_read_failure'}(cv => $cv, obj => $args{'obj'}),
        on_return  => $args{'on_return'}(cv => $cv, obj => $args{'obj'}),
        on_close   => $args{'on_close'}(obj => $args{'obj'})
	);

    my $status = $cv->recv();
    
    if(!$status){
        return;
    }
    
    return $ar;
}

=head2 on_read_failure

=cut
sub on_read_failure{
    return sub {
	
    };
}


=head2 on_close_handler

=cut

sub on_close_handler{
    my %params = @_;

    return sub {
        my $obj = $params{'obj'};
        $obj->logger->error("Connection to RabbitMQ Closed");
        if($obj->consuming){
            $obj->stop_consuming();
        }
    };

}

=head2 on_client_close_handler

=cut
sub on_client_close_handler{
    my %params = @_;

    return sub {
        my $obj = $params{'obj'};
        $obj->logger->error("Connection to RabbitMQ Closed");
        $obj->_set_connected(0);
    };

}

=head2 on_failure_handler

=cut

sub on_failure_handler{
    my %params = @_;

    return sub{
        $params{'obj'}->logger->error("Error connecting");
	$params{'cv'}->send(0);
    };

}

=head2 channel_creator

=cut

sub channel_creator{
    my %params = @_;
    
    return sub{
        my $r = shift;
        $params{'obj'}->logger->info("Successfully connected to RabbitMQ");
        $r->open_channel( on_success => GRNOC::RabbitMQ::exchange_creator( %params ),
			  on_failure => GRNOC::RabbitMQ::on_failure_handler( %params ),
			  on_close   => GRNOC::RabbitMQ::on_close_handler( %params) );
    };
}

=head2 exchange_creator

=cut

sub exchange_creator{
    my %params = @_;

    return sub {
	my $channel = shift;
        $params{'obj'}->logger->info("Successfully created RabbitMQ Channel");
        $params{'obj'}->_set_channel($channel);
	$channel->declare_exchange( exchange => $params{'exchange'},
				    type => $params{'type'},
				    on_success => GRNOC::RabbitMQ::queue_declare( %params ),
				    on_failure => GRNOC::RabbitMQ::on_failure_handler( %params ) );
    };
}

=head2 queue_declare

=cut

sub queue_declare{
    my %params = @_;
    
    return sub {
        $params{'obj'}->logger->info("Successfully created RabbitMQ Exchange");
	$params{'obj'}->channel->declare_queue( exclusive => $params{'exclusive'},
				 queue => $params{'queue'},
				 on_success => sub {
				     my $method = shift;
                                     $params{'obj'}->logger->info("Successfully created Queue!");
				     $params{'obj'}->_set_queue($method->method_frame->queue);
				     $params{'obj'}->_set_connected(1);
                                     $params{'cv'}->send(1);
				 },
				 on_failure => sub {
                                     $params{'obj'}->logger->error("Unable to create Queue");
				     $params{'cv'}->send(0);
				 });
    };
}

1;
