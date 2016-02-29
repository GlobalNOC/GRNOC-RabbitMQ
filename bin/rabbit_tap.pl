#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use DateTime;
use GRNOC::CLI;

sub main{

    my $cli = GRNOC::CLI->new();
    
    $cli->clear_screen();

    my $username = $cli->get_input("Username");
    my $password = $cli->get_password("Password");
    my $host     = $cli->get_input("Host", default => "localhost");
    my $port     = $cli->get_input("Port", default => "5672");
    my $vhost    = $cli->get_input("VHost", default => "/");
    my $exchange = $cli->get_input("Exchange");
    
    my $topic   = $cli->get_input("Topic", default => "#");
    
    $cli->clear_screen();

    my $cv = AnyEvent->condvar;
    my $rabbit_mq;

    my $ar = AnyEvent::RabbitMQ->new->load_xml_spec()->connect(
        host => $host,
        port => $port,
        user => $username,
        pass => $password,
        vhost => $vhost,
        timeout => 1,
        tls => 0,
        on_success => sub {
            my $r = shift;
                $r->open_channel(
                    on_success => sub {
                        my $channel = shift;
                        $rabbit_mq = $channel;
                            $channel->declare_exchange(
                                exchange   => $exchange,
                                type => 'topic',
                                on_success => sub {
                                    $cv->send();
                                },
                                on_failure => $cv,
                                );
                    },
                    on_failure => $cv,
                    on_close   => sub {
                        warn "Disconnected from RabbitMQ!";
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

    $cv = AnyEvent->condvar;
    
    $rabbit_mq->declare_queue( exclusive => 1,
			       on_success => sub {
				   my $queue = shift;
				   $rabbit_mq->bind_queue( queue => $queue->{method_frame}->{queue},
							   exchange => $exchange,
							   routing_key => $topic,
							   on_success => sub {
							       $cv->send($queue);
							   });
				   
			       });
    my $queue = $cv->recv();
    
    
    $rabbit_mq->consume( queue => $queue->{method_frame}->{queue},
			 on_consume => sub {
			     my $message = shift;
			     print_messages($message);
			 });    
    

    AnyEvent->condvar->recv;
}

sub print_messages{
    my $message = shift;

    my $header = $message->{'header'};
    my $routing_key = $message->{'deliver'}->{'method_frame'}->{'routing_key'};
    my $body = $message->{'body'}->{'payload'};
    
    my $date = DateTime->from_epoch(epoch => $header->{'timestamp'});
    
    my $date_str = $date->mdy('/') . "T" . $date->hms(':');

    if(defined($header->{'reply_to'})){
	print $date_str . " to: " . $routing_key . ", from: " . $header->{'user_id'} . "@" . $header->{'reply_to'} . ", correlation_id: " . $header->{'correlation_id'} . ", Body: " . $body . "\n";
    }else{
	print $date_str . " to: " . $routing_key . ", from: " . $header->{'user_id'} . ", Body: " . $body . "\n";
    }
}

main();
