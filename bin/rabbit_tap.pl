#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::Config;
use DateTime;
use GRNOC::CLI;

use Data::Dumper;

my $config_file;

GetOptions('config|c=s' => \$config_file);

sub main{

    my $cli = GRNOC::CLI->new();
    
    $cli->clear_screen();

    my ($username, $password, $host, $port, $vhost, $exchange, $topic);

    if($config_file){
        if(! -e $config_file){
            die("Unable to find config file: $config_file");
        }

        my $config = new GRNOC::Config( config_file => $config_file, force_array => 0 );
        $username = $config->get( '/config/username' );
        $password = $config->get( '/config/password' );
        $host     = $config->get( '/config/host' );
        $port     = $config->get( '/config/port' );
        $vhost    = $config->get( '/config/vhost' );
        $exchange = $config->get( '/config/exchange' );
        $topic    = $config->get( '/config/topic' );

    }
    else{

        $username = $cli->get_input("Username");
        $password = $cli->get_password("Password");
        $host     = $cli->get_input("Host", default => "localhost");
        $port     = $cli->get_input("Port", default => "5672");
        $vhost    = $cli->get_input("VHost", default => "/");
        $exchange = $cli->get_input("Exchange");
        $topic   = $cli->get_input("Topic", default => "#");
    
        $cli->clear_screen();
    }

    if(!$username || !$password || !$host || !$port || !$vhost || ! $exchange || !$topic){
        die("Missing parameters.");
    }

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

    if(!defined($header->{'timestamp'})){
	$header->{'timestamp'} = time();
    }

    my $date = DateTime->from_epoch(epoch => $header->{'timestamp'});
    my $date_str = $date->mdy('/') . "T" . $date->hms(':');

    if(!defined($header->{'user_id'})){
	$header->{'user_id'} = "UNKNOWN USER";
    }

    if(defined($header->{'reply_to'})){
	print $date_str . " to: " . $routing_key . ", from: " . $header->{'user_id'} . "@" . $header->{'reply_to'} . ", correlation_id: " . $header->{'correlation_id'} . ", Body: " . $body . "\n";
    }else{
	print $date_str . " to: " . $routing_key . ", from: " . $header->{'user_id'} . ", Body: " . $body . "\n";
    }
}

main();
