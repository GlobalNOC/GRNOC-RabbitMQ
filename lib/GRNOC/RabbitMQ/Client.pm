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
use Time::HiRes qw( gettimeofday tv_interval);
use Data::Dumper;

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
use AnyEvent;
use Data::Dumper;

sub main{

    my $client = GRNOC::RabbitMQ::Client->new(topic => "OF.FWDCTL",
                                              exchange => 'OESS',
                                              user => 'guest',
                                              pass => 'guest');

    # synchronous call
    my $res = $client->plus(a => 2, b => 2);
    warn Data::Dumper::Dumper($res);

    # asynchronous call
    my $cv = AnyEvent->condvar;
    $client->plus(a => 2,
                  b => 2,
                  async_callback => sub {
                      my $res = shift;
                      warn Data::Dumper::Dumper($res);
                      $cv->send;
                  });
    $cv->recv;
}

main();

=cut

=head2 new

=cut

sub new{
    my $class = shift;
    
    my %args = ( host => 'localhost',
		 port => 5672,
		 user => undef,
		 pass => undef,
		 vhost => '/',
		 timeout => 15,
		 queue => undef,
		 topic => undef,
		 exchange => '',
		 @_ );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('GRNOC.RabbitMQ.Client');

    $self->{'uuid'} = new Data::UUID;
    bless $self, $class;

    $self->{'pending_responses'} = {};
    
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
	    die "Unable to deliver ", Data::Dumper::Dumper($frame);
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

    $self->{'logger'}->debug("Connected to Rabbit");

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
                                  on_consume => $self->on_response_cb()
	);
    
    return;
}

sub _generate_uuid{
    my $self = shift;
    return $self->{'uuid'}->to_string($self->{'uuid'}->create());
}

=head2 on_response_cb

=cut

sub on_response_cb {
    my $self = shift;
    return  sub {
	my $var = shift;
	my $body = $var->{body}->{payload};
        
	my $end = [gettimeofday];

        $self->{'logger'}->debug("on_response_cb callback args: " . Data::Dumper::Dumper($var));

        $self->{'logger'}->debug("Pending Responses: " . Data::Dumper::Dumper($self->{'pending_responses'}));
        
        my $corr_id = $var->{header}->{correlation_id};
        if (defined $self->{'pending_responses'}->{$corr_id}) {
            $self->{'logger'}->debug("on_response_db callback result: " . $body);
	    $self->{'logger'}->debug("total time: " . tv_interval( $self->{'pending_responses'}->{$corr_id}->{'start'}, $end));
            $self->{'pending_responses'}->{$corr_id}->{'cb'}(decode_json($body));
            delete $self->{'pending_responses'}->{$corr_id};
        } else {
            $self->{'logger'}->debug("I don't know what to do with corr_id: $corr_id");
        }
    };
}

sub AUTOLOAD{
    my $self = shift;

    my $name = our $AUTOLOAD;

    my @stuff = split('::', $name);
    $name = pop(@stuff);
    $self->{'logger'}->debug("Running name: " . $name . "\n");
    $self->{'logger'}->debug("Params: " . Data::Dumper::Dumper(@_));
    my $params = {
	@_
    };

    if(defined($params->{'no_reply'}) && $params->{'no_reply'} == 1){
	delete $params->{'no_reply'};
	$self->{'rabbit_mq'}->publish(
	    exchange => $self->{'exchange'},
	    routing_key => $self->{'topic'} . "." . $name,
	    header => {
		no_reply => 1,
	    },
	    body => encode_json($params)
	    );
	return;
    }else{
	delete $params->{'no_reply'};
        my $do_async = 0;
        my $cv = AnyEvent->condvar;

        my $callback = sub { my $results = shift; $cv->send($results)};
        if(defined($params->{'async_callback'})){
            $callback = $params->{'async_callback'};
            delete $params->{'async_callback'};
            $do_async = 1;
        }
        
	my $corr_id = $self->_generate_uuid();
        $self->{'pending_responses'}->{$corr_id}{'cb'} = $callback;
	$self->{'pending_responses'}->{$corr_id}{'start'} = [gettimeofday];

        $self->{'logger'}->debug("Correlation ID: " . $corr_id);
        
	$self->{'rabbit_mq'}->publish(
	    exchange => $self->{'exchange'},
	    routing_key => $self->{'topic'} . "." . $name,
	    header => {
		reply_to => $self->{'callback_queue'},
		correlation_id => $corr_id,
	    },
	    body => encode_json($params)
	    );


        my $timeout;
        $timeout = AnyEvent->timer( after => $self->{'timeout'}, 
                                    cb => sub{
                                        if(!defined($self->{'pending_responses'}->{$corr_id})) {
                                            return;
                                        }
                                        my $cb = $self->{'pending_responses'}->{$corr_id}{'cb'};
                                        # deleting the pending response before calling back ensures $cb is only called once
                                        delete $self->{'pending_responses'}->{$corr_id};

                                        my $err = {error => "Timeout occured waiting for response"};
                                        if($do_async){
                                            &$cb($err);
                                        }else{
                                            $cv->send($err);
                                        }

                                        # needed to keep $timeout from being GCed before the timer fires
                                        undef $timeout;
                                    });

        if(!$do_async){
            my $res = $cv->recv();
            return $res;
        }
        
        $self->{'logger'}->debug("Moving on...")
    }
}

sub DESTROY{

}

1;
