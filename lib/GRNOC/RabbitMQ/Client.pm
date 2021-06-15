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

use AnyEvent;
use GRNOC::RabbitMQ;
use Data::UUID;
use GRNOC::Log;
use JSON::XS;
use Moo;
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

=head2 BUILD

=head2 Constructor Arguments / Attributes
=item port
=item user
=item pass
=item host
=item vhost
=item timeout
=item prefetch_count
=item queue_name
=item topic
=item topic
=item exchange
=item auto_reconnect
=item on_success
=item on_failure
=item on_read_failure
=item on_return
=item on_close

=head2 Internal Objects
=item uuid
=item logger
=item pending_responses
=item connected
=item channel
=item queue
=item consuming
=item callback_queue
=item ar

=cut

has port => (is => 'rwp', default => 5672, required => 1);;
has user => (is => 'rwp', default => 'guest', required => 1);
has pass => (is => 'rwp', required => 1);
has host => (is => 'rwp', default => 'localhost', required => 1);
has vhost => (is => 'rwp', default => '/', required => 1);
has timeout => (is => 'rwp', default => 15, required => 1);
has prefetch_count => (is => 'rwp', default => 1, required => 1);
has queue_name => (is => 'rwp');
has topic => (is => 'rw', required => 1);
has exchange => (is => 'rwp', required => 1);
has auto_reconnect => (is => 'rw', default => 0);
has on_success => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::channel_creator }, required => 1);
has on_failure => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::on_failure_handler}, required => 1);
has on_read_failure => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::on_failure_handler}, required => 1);
has on_return => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::on_failure_handler}, required => 1);
has on_close => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::on_client_close_handler}), required => 1;

has uuid => (is => 'rwp');
has logger => (is => 'rwp');
has pending_responses => (is => 'rwp');
has connected => (is => 'rwp');
has channel => (is => 'rwp');
has queue => (is => 'rwp');
has consuming => (is => 'rwp');
has callback_queue => (is => 'rwp');
has ar => (is =>'rwp');


sub BUILD{
    my ($self) = @_;
    
    $self->_set_logger(GRNOC::Log->get_logger('GRNOC.RabbitMQ.Client'));
    $self->_set_uuid(Data::UUID->new);
    $self->_set_pending_responses({});
    $self->_connect();
    return $self;
}

sub _connect{
    my $self = shift;
    
    $self->logger->debug("Connecting to RabbitMQ");

    my $ar = GRNOC::RabbitMQ::connect_to_rabbit(
        host => $self->host,
        port => $self->port,
        user => $self->user,
        pass => $self->pass,
        vhost => $self->vhost,
        timeout => $self->timeout,
        prefetch_count => $self->prefetch_count,
        tls => 0,
        exchange => $self->exchange,
        type => 'topic',
        obj => $self,
        exclusive => 1,
        queue => $self->queue_name,
        on_success => $self->on_success,
        on_failure => $self->on_failure,
        on_read_failure => $self->on_read_failure,
        on_return => $self->on_return,
        on_close => $self->on_close
        );

    if(!defined($ar)){
        $self->logger->error("Unable to connect to RabbitMQ.");
        return;
    }

    $self->_set_ar($ar);

    if(!$self->connected){
        $self->logger->error("Error connecting to RabbitMQ");
        return;
    }

    $self->logger->debug("Connected to Rabbit");

    my $cv = AnyEvent->condvar;

    $self->channel->bind_queue( exchange => $self->exchange,
                                queue => $self->queue,
                                routing_key => $self->queue,
                                on_success => sub {
                                    $cv->send($self->queue);
                                });
    
    my $cbq = $cv->recv();
    $self->_set_callback_queue($self->queue);
    
    $self->_set_consuming(1);
    
    $self->channel->consume(
        no_ack => 0,
        on_consume => $self->on_response_cb()
        );
        

    return 1;
}


=head2 stop_consuming

=cut

sub stop_consuming{
    my $self = shift;
    $self->_set_consuming(0);
}



sub _generate_uuid{
    my $self = shift;
    return $self->uuid->to_string($self->uuid->create());
}

=head2 on_response_cb

=cut
sub on_response_cb {
    my $self = shift;
    return  sub {
        my $var = shift;
        my $body = $var->{body}->{payload};
        
        my $end = [gettimeofday];
        
        $self->logger->debug("on_response_cb callback args: " . Data::Dumper::Dumper($var));
        $self->logger->debug("Pending Responses: " . Data::Dumper::Dumper($self->pending_responses));
        
        my $corr_id = $var->{header}->{correlation_id};
        if (defined $self->{'pending_responses'}->{$corr_id}) {
            $self->logger->debug("on_response_db callback result: " . $body);
            $self->logger->debug("total time: " . tv_interval( $self->pending_responses->{$corr_id}->{'start'}, $end));

            my $cb = $self->pending_responses->{$corr_id}{'cb'};

            delete $self->pending_responses->{$corr_id}->{'cb'};
            delete $self->pending_responses->{$corr_id}->{'timeout'};
            delete $self->pending_responses->{$corr_id};

            my $decoded_body;
            eval {
                $decoded_body = decode_json($body);
            };

            if(!defined($decoded_body)){
                warn "Unable to decode JSON String: " . $body . "\n";
                warn "JSON Parser error: " . $@ . "\n";
                $self->logger->error("Unable to decode JSON String: " . $body);
                $self->logger->error("JSON Parser error: " . $@);
                $decoded_body = { error => "unable to decode JSON string: " . $body};
            }

            &$cb(decode_json($body));
            #if the callback takes a long time to update the timers may get screwed up
            #we update the now_update to update it
            AnyEvent->now_update;
        } else {
            $self->logger->debug("I don't know what to do with corr_id: $corr_id");
        }

        $self->channel->ack();
    };
}

sub AUTOLOAD{
    my $self = shift;

    my $name = our $AUTOLOAD;

    # Don't need to do anything for the destructor
    return if ($name =~ /DESTROY$/);

    $self->logger->debug("Calling: " . $name);

    if(!$self->connected){
        $self->logger->debug("Not connected to rabbit.");

        if($self->auto_reconnect()){
            $self->logger->debug("Attempting to reconnect to Rabbit.");

            #--- try to reconnect, error out if we can't
            my $res = $self->_connect();

            if(!$res){
                return;
            }
        }
        else{
            $self->logger->debug('Auto Reconnect disabled. Returning.');
            return;
        }
    }
    
    
    my @stuff = split('::', $name);
    $name = pop(@stuff);
    $self->logger->debug("Running name: " . $name . "\n");
    $self->logger->debug("Params: " . Data::Dumper::Dumper(@_));
    my $params = {
        @_
    };
    
    $self->logger->debug("Topic: " . $self->topic . "." . $name);

    if(defined($params->{'no_reply'}) && $params->{'no_reply'} == 1){
        delete $params->{'no_reply'};
        $self->channel->publish(
            exchange => $self->exchange,
            routing_key => $self->topic . "." . $name,
            header => {
                no_reply => 1,
            },
            body => encode_json($params)
            );
        return 1;
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
        $self->pending_responses->{$corr_id}{'cb'} = $callback;
        $self->pending_responses->{$corr_id}{'start'} = [gettimeofday];
        
        $self->logger->debug("Correlation ID: " . $corr_id);
        
        $self->channel->publish(
            exchange => $self->exchange,
            routing_key => $self->topic . "." . $name,
            header => {
                reply_to => $self->callback_queue,
                correlation_id => $corr_id,
            },
            body => encode_json($params)
            );
        
	# Make sure AnyEvent knows where now is before we make a timer, anything
	# calling this might have been doing sleeps or other event control
	AnyEvent->now_update;
        
        $self->pending_responses->{$corr_id}->{'timeout'} = AnyEvent->timer( after => $self->timeout,
                                                                             cb => sub{
                                                                                 if (!defined $self->pending_responses->{$corr_id}) {
                                                                                     return;
                                                                                 }

                                                                                 my $cb = $self->pending_responses->{$corr_id}{'cb'};

                                                                                 delete $self->pending_responses->{$corr_id}->{'cb'};
                                                                                 delete $self->pending_responses->{$corr_id}->{'timeout'};
                                                                                 delete $self->pending_responses->{$corr_id};

                                                                                 my $err = {error => "Timeout occured waiting for response"};
                                                                                 if ($do_async) {
                                                                                     &$cb($err);
                                                                                 } else {
                                                                                     $cv->send($err);
                                                                                 }
                                                                             });
        
        if (!$do_async) {
            my $res = $cv->recv();
            return $res;
        }
        
        $self->logger->debug("Moving on...")
    }
}

# Defined to prevent AUTOLOAD from trying to do this
sub DESTROY { }

1;
