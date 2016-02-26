#--------------------------------------------------------------------
#----- GRNOC RabbitMQ Dispatcher Library
#-----
#----- Copyright(C) 2015 The Trustees of Indiana University
#--------------------------------------------------------------------
#----- 
#----- This module wraps much of the common Rabbit related to code
#----- especially for RPC server side, and creating methods
#----- reasonably easy to develop with.
#--------------------------------------------------------------------

use strict;
use warnings;

package GRNOC::RabbitMQ::Dispatcher;

use AnyEvent::RabbitMQ;
use AnyEvent;
use GRNOC::Log;

=head1 NAME

GRNOC::RabbitMQ::Dispatcher - GRNOC centric RabbitMQ RPC Dispatcher

=head1 SYNOPSIS

This modules provides AMQP programmers with an abstracted JSON/AMQP base 
object.  The object handles the taks of input/param validation.

It takes care of handling the response back to the caller over Rabbit.

Here is an example of how to use this

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;

sub main{

    my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(queue => "OF.FWDCTL",
                                                      exchange => 'OESS',
                                                      user => 'guest',
                                                      pass => 'guest');

    my $method = GRNOC::RabbitMQ::Method->new( name => "do_stuff",
                                               callback => \&do_stuff,
                                               description => "Does stuff" );
    $method->set_schema_validator( schema => {});

    $dispatcher->register_method( $method );

    $dispatcher->start_consuming();
}

sub do_stuff{
    my $json = shift;

    warn "\o/ it just works\n";

    return {success => 1};
}

main();

=cut

sub new{
    my $that  = shift;
    my $class =ref($that) || $that;
    
    my %args = (
	debug                => 0,
	host => 'localhost',
	port => 5672,
	user => undef,
	pass => undef,
	vhost => '/',
	timeout => 1,
	queue => undef,
	exchange => '',
	@_,
	);

    my $self = \%args;

    #--- register builtin help method
    bless $self,$class;

    $self->{'logger'} = GRNOC::Log->get_logger();

    if(!defined($self->{'queue'})){
	$self->{'logger'}->error("No Queue defined!!!");
	return;
    }

    $self->_connect_to_rabbit();

    #--- register the help method
    my $help_method = GRNOC::RabbitMQ::Method->new(
	name         => "help",
	description  => "The help method!",
	is_default   => 1,
	callback     => \&help,
	);

    $help_method->set_schema_validator(
	schema => { 'type' => 'object',
		    'properties' => { "method_name" => {'type' => 'string'} }}
	);
    
    $self->register_method($help_method);
    
    
    return $self;
    
}

sub _connect_to_rabbit{
    
    my $self = shift;

    $self->{'logger'}->debug("Connecting to RabbitMQ");

    my $cv = AnyEvent->condvar;
    my $rabbit_mq;

    my $ar = AnyEvent::RabbitMQ->new->load_xml_spec()->connect(
	host => $self->{'host'},
	port => $self->{'port'},
	user => $self->{'user'},
	pass => $self->{'pass'},
	vhost => $self->{'vhost'},
	timeout => $self->{'timeout'},
	tls => 0,
	on_success => sub {
	    my $r = shift;
	        $r->open_channel(
		    on_success => sub {
			my $channel = shift;
			$rabbit_mq = $channel;
			    $channel->declare_exchange(
				exchange   => $self->{'exchange'},
				type => 'topic',
				on_success => sub {
				    $cv->send();
				},
				on_failure => $cv,
				);
		    },
		    on_failure => $cv,
		    on_close   => sub {
			$self->{'logger'}->error("Disconnected from RabbitMQ!");
		    },
		    );
	},
	on_failure => $cv,
	on_read_failure => sub { die @_ },
	on_return  => sub {
	    my $frame = shift;
	    die "Unable to deliver ", Dumper($frame);
	},
	on_close   => sub {
	    my $why = shift;
	    if (ref($why)) {
		my $method_frame = $why->method_frame;
		die $method_frame->reply_code, ": ", $method_frame->reply_text;
	    }
	    else {
		die $why;
	    }
	}
	);
    
    #synchronize
    $cv->recv();

    $self->{'ar'} = $ar;
    $self->{'rabbit_mq'} = $rabbit_mq;

    if(!defined($rabbit_mq)){
	die "unable to connect to RabbitMQ";
    }

    $cv = AnyEvent->condvar;
    
    $self->{'rabbit_mq'}->declare_queue( 
					 on_success => sub {
					     my $queue = shift;
					     $self->{'rabbit_mq'}->bind_queue( queue => $queue->{method_frame}->{queue},
									       exchange => $self->{'exchange'},
									       routing_key => $self->{'queue'} . '.*',
									       on_success => sub {
										   $cv->send($queue);
									       });

					 });
    my $queue = $cv->recv();

    my $dispatcher = $self;
    $self->{'rabbit_mq'}->consume( queue => $queue->{method_frame}->{queue},
                                   on_consume => sub {
                                       my $message = shift;
                                       $dispatcher->handle_request($message);
                                   });
    
    return;

}


=head2 help()
returns list of avail methods or if parameter 'method_name' provided, the details about that method
=cut
sub help{
    my $m_ref   = shift;
    my $params  = shift;

    my %results;

    my $method_name = $params->{'method_name'}{'value'};
    my $dispatcher = $m_ref->get_dispatcher();

    if (!defined $method_name) {
	return $dispatcher->get_method_list();
    }
    else {
	my $help_method = $dispatcher->get_method($method_name);
	if (defined $help_method) {
	    return $help_method->help();
	}
	else {
	    $m_ref->set_error("unknown method: $method_name\n");
	    return undef;
	}
    }
}


#----- formats results in JSON then seddts proper cache directive header and off we go
sub _return_error{
    my $self        = shift;
    my $reply_to    = shift;
    my $rabbit_mq_connection = $self->{'rabbit_mq'};

    my %error;

    $error{"error"} = 1;
    $error{'error_text'} = $self->get_error();
    $error{'results'} = undef;
    
    if(!defined($reply_to->{'routing_key'})){
	$rabbit_mq_connection->ack();
	return;

    }
    
    $rabbit_mq_connection->publish( exchange => $reply_to->{'exchange'},
				    routing_key => $reply_to->{'routing_key'},
				    header => {'correlation_id' => $reply_to->{'correlation_id'}},
				    body => JSON::XS::encode_json(\%error));
    $rabbit_mq_connection->ack();
    
}


=head2 handle_request

=cut

sub handle_request{
    my $self = shift;
    my $var = shift;

    my $state = $self->{'state'};
    my $reply_to = {};
    if(defined($var->{'header'}->{'no_reply'}) && $var->{'header'}->{'no_reply'} == 1){

	$self->{'logger'}->debug("No Reply specified");
	
    }else{
	$self->{'logger'}->debug("Has reply specified");
	$reply_to->{'exchange'} = $var->{'deliver'}->{'method_frame'}->{'exchange'};
	$reply_to->{'correlation_id'} = $var->{'header'}->{'correlation_id'},
	$reply_to->{'routing_key'} = $var->{'header'}->{'reply_to'};
    }

    my $full_method = $var->{'deliver'}->{'method_frame'}->{'routing_key'};

    my $queue_name = $self->{'queue'};
    $full_method =~ /$queue_name\.(\S+)/;

    my $method = $1;

    if(!defined($method)){
	$method = "help";
    }

    #--- check for properly formed method
    if (!defined $method) {
	$self->_set_error("format error with method name");
	$self->_return_error($reply_to);
	return undef
    }

    #--- check for method being defined
    if (!defined $self->{'methods'}{$method}) {
	$self->_set_error("unknown method: $method");
	$self->_return_error($reply_to);
	return undef;
    }
    
    #--- have the method do its thing;
    $self->{'methods'}{$method}->handle_request( $self->{'rabbit_mq'},
						 $reply_to,
						 $var->{'body'}->{'payload'}, $self->{'default_input_validators'},
						 $state);

    return 1;
}


=head2 get_method_list()
Method to retrives the list of registered methods
=cut

sub get_method_list{
    my $self        = shift;

    my @methods =  sort keys %{$self->{'methods'}};
    return \@methods;

}


=head2 get_method($name)
returns method ref based upon specified name
=cut

sub get_method{
    my $self        = shift;
    my $name  = shift;

    return $self->{'methods'}{$name};
}



=head2 get_error()
gets the last error encountered or undef.
=cut

sub get_error{
    my $self  = shift;
    return $self->{'error'};
}


=head2 _set_error()
protected method which sets a new error and prints it to stderr
=cut

sub _set_error{
    my $self  = shift;
    my $error = shift;

    $self->{'logger'}->error($error);
    $self->{'error'} = $error;
}


=head2 register_method()
This is used to register a web service method.  Three items are needed
to register a method: a method name, a function callback and a method configuration.
The callback will accept one input argument which will be a reference to the arguments
structure for that method, with the "value" attribute added.
The callback should return a pointer to the results data structure.
=cut
sub register_method{
    my $self  = shift;
    my $method_ref  = shift;

    my $method_name = $method_ref->get_name();
    if (!defined $method_name) {
	$self->{'logger'}->error(ref $method_ref."->get_name() returned undef");
	return;
    }

    if (defined $self->{'methods'}{$method_name}) {
	$self->logger->error("$method_name already exists");
	return;
    }

    $self->{'methods'}{$method_name} = $method_ref;
    if ($method_ref->{'is_default'}) {
	$self->{'default_method'} = $method_name;
    }
    #--- set the Dispatcher reference
    $method_ref->set_dispatcher($self);

    return 1;
}

=head2 start_consuming

please note that start_consuming will block forever in your application

=cut

sub start_consuming{
    my $self = shift;
    my $state = shift;
    $self->{'state'} = $state;
    AnyEvent->condvar->recv;
}

1;
