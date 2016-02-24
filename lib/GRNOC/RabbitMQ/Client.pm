#--------------------------------------------------------------------
#----- GRNOC RabbitMQ Client Library
#-----
#----- Copyright(C) 2015 The Trustees of Indiana University
#--------------------------------------------------------------------
#----- 
#----- This module wraps much of the common Rabbit related to code
#----- especially for RPC calls to Rabbit RPC servers and makes it
#----- reasonably easy to develop with.
#--------------------------------------------------------------------

use strict;
use warnings;

package GRNOC::RabbitMQ::Client;

use AnyEvent::RabbitMQ;
use AnyEvent;
use Data::UUID;
use GRNOC::Log;
use JSON::XS;

=head1 NAME

GRNOC::RabbitMQ::Client - GRNOC RabbitMQ RPC Client handler

=head1 SYNOPSIS

This module provides Rabbit MQ programers and abstraction about the JSON/AMQP 
base service objects.  This module implements a blocking RPC or "fire and forget"
AMQP client.

Please note that currently much work is still to be done on this module, 
specifically with handling errors.

Results from RPC calls will always be perl Objects.

Here is a quick example on how to use this module

use strict;
use warnings;

use GRNOC::RabbitMQ::Client;
use Data::Dumper;

sub main{

    my $client = GRNOC::RabbitMQ::Client->new(queue => "OF.FWDCTL",
                                              exchange => 'OESS',
                                              user => 'guest',
                                              pass => 'guest');

    my $res = $client->do_stuff();
    warn Data::Dumper::Dumper($res);

}

main();

=cut


sub new{
    my $class = shift;
    
    my %args = ( host => 'localhost',
		 port => 5672,
		 user => undef,
		 pass => undef,
		 vhost => '/',
		 timeout => 1,
		 queue => undef,
		 exchange => '',
		 @_ );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('GRNOC.RabbitMQ.Client');

    $self->{'uuid'} = new Data::UUID;
    bless $self, $class;
    
    $self->_connect();

    return $self;
}

sub _connect{
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

    $self->{'logger'}->debug("");

    $cv = AnyEvent->condvar;

    $self->{'ar'} = $ar;
    $self->{'rabbit_mq'} = $rabbit_mq;
    $self->{'rabbit_mq'}->declare_queue( exclusive => 1,
					 on_success => sub {
					     my $queue = shift;
					     $self->{'rabbit_mq'}->bind_queue( exchange => $self->{'exchange'},
									       queue => $queue->{method_frame}->{queue},
									       routing_key => $queue->{method_frame}->{queue},
									       on_success => sub {
										   $cv->send($queue->{method_frame}->{queue});
									       });
					 });
    
    my $cbq = $cv->recv();
    $self->{'callback_queue'} = $cbq;

    $self->{'rabbit_mq'}->consume(
        no_ack => 1,
        on_consume => $self->on_response_cb(),
	);
    
    return;
}

sub _generate_uuid{
    my $self = shift;
    return $self->{'uuid'}->to_string($self->{'uuid'}->create());
}

sub on_response_cb {
    my $self = shift;
    return  sub {
	my $var = shift;
	my $body = $var->{body}->{payload};
	if ($self->{correlation_id} eq $var->{header}->{correlation_id}) {
	    $self->{cv}->send($body);
	}
    };
}

sub AUTOLOAD{
    my $self = shift;

    my $name = our $AUTOLOAD;

    my @stuff = split('::', $name);
    $name = pop(@stuff);

    my $params = {
	@_
    };

    my $cv = AnyEvent->condvar;
    my $corr_id = $self->_generate_uuid();

    $self->{'correlation_id'} = $corr_id;
    $self->{'cv'} = $cv;

    $self->{'rabbit_mq'}->publish(
        exchange => $self->{'exchange'},
        routing_key => $self->{'queue'} . "." . $name,
        header => {
            reply_to => $self->{'callback_queue'},
            correlation_id => $corr_id,
        },
        body => encode_json($params)
    );

    my $res = $cv->recv;

    return decode_json($res);
}

sub DESTROY{

}

1;
