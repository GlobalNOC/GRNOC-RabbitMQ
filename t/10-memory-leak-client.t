#!/us/bin/perl

use strict;
use warnings;

use GRNOC::RabbitMQ::Client;

use Test::More tests => 2;
use Cwd;
use Proc::Daemon;
use AnyEvent;

use Devel::Size;

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;

use Data::Dumper;

my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
    queue => "Test",
    exchange => "Test",
    topic => "Test.Data",
    user => "guest",
    pass => "guest",
    port => "5672"
    );

my $method = GRNOC::RabbitMQ::Method->new(
    name => "foo",
    async => 0,
    description => "does nothing",
    callback => sub { my $mref = shift; my $pref = shift;
                      return {status => $pref->{'val'}{'value'}};
    });
                      
$method->add_input_parameter(
    name => 'val',
    description => "value",
    pattern => '(.*)' );
$dispatcher->register_method($method);

my $client = GRNOC::RabbitMQ::Client->new(
    topic => "Test.Data",
    exchange => "Test",
    user => "guest",
    pass => "guest"
    );

my $res;

my @chars=('a'..'z','A'..'Z','0'..'9','_');

my $size;

my $i = 0;
while($i<1000){

    my $random_string = "";
    foreach (1..100) 
    {
        # rand @chars will generate a random 
        # number between 0 and scalar @chars
        $random_string.=$chars[rand @chars];
    }
    
    $res = $client->foo( val => $random_string );

    # grab the size of the dispatcher after handling the first few requests, ie after "warm up"
    if ($i++ == 5){
        $size = Devel::Size::total_size($dispatcher);
        diag("sizeof sync dispatcher is $size");        
    }
}

my $new_size = Devel::Size::total_size($dispatcher);
diag("sizeof sync dispatcher is now $new_size (original = $size)");

my $growth = $new_size - $size;

ok($growth < 1000, "tolerable growth in size of of process - sync");

$method = GRNOC::RabbitMQ::Method->new(
    name => "foo2",
    description => "doesn't do anything",
    async => 1,
    callback => sub { my $mref = shift; my $pref = shift; $mref->{'success_callback'}( {status => $pref->{'val'}{'value'}})});

$method->add_input_parameter(
    name => 'val',
    description => "value",
    pattern => '(.*)' );

$dispatcher->register_method($method);

$i=0;
while($i<1000){
    
    my @chars=('a'..'z','A'..'Z','0'..'9','_');
    my $random_string;
    foreach (1..100)
    {
        # rand @chars will generate a random
        # number between 0 and scalar @chars
        $random_string.=$chars[rand @chars];
    }
    
    $client->foo( val => $random_string,
                  async_callback => sub {
                      $res = shift;
                      #warn Dumper($res);
                      $dispatcher->stop_consuming();
                  });
    
    $dispatcher->start_consuming();

    # grab the size of the dispatcher after handling the first few requests, ie after "warm up"
    if ($i++ == 5){
        $size = Devel::Size::total_size($dispatcher);
        diag("sizeof async dispatcher is $size");
    }


}

$new_size = Devel::Size::total_size($dispatcher);
diag("sizeof sync dispatcher is now $new_size (original = $size)");

$growth = $new_size - $size;

ok($growth < 1000, "tolerable growth in size of of process - async");
