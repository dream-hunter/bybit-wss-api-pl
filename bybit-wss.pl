#!/usr/bin/env perl

use strict;
use IO::Async::Loop;
use Net::Async::WebSocket::Client;
use IO::Async::Timer::Periodic;
use JSON;
use POSIX;
use Data::Dumper;
use Digest::SHA qw(hmac_sha512_hex sha512_hex hmac_sha256_hex sha256_hex);

use feature qw( switch );
no warnings qw( experimental::smartmatch );
our $loglevel = 3;

my $host = "stream.bybit.com";
my $port = "443";
my $heartbeat_interval = 60;
my $heartbeat;
my $api_key    = $ARGV[0];
my $api_secret = $ARGV[1];
#################################
# Async Web Socket Client handler
#################################
while (1) {
    my $timer  = undef;
    my $pinger = undef;
    my $req_id = {
        'pub'  => 0,
        'prv'  => 0
    };
    my $client = {
        'pub'  => 0,
        'prv'  => 0
    };
    my $loop   = undef;
    $heartbeat = {
        'pub' => time+$heartbeat_interval,
        'prv' => time+$heartbeat_interval
    };
    $timer = IO::Async::Timer::Periodic->new(
        interval=> 10,
        on_tick => sub {
# Heartbeat
            $heartbeat->{'err'} = undef;
            if ($heartbeat->{'pub'} < time) {
                logMessage("Public Heartbeat error " . $heartbeat->{'pub'} . " < ". time . "\n", 1);
                $heartbeat->{'err'} = 1;
            } else {
                logMessage("Public Heartbeat is fine " . $heartbeat->{'pub'} . " > ". time . "\n", 4);
            }
            if (defined $api_key && defined $api_secret && $heartbeat->{'prv'} < time) {
                logMessage("Private Heartbeat error " . $heartbeat->{'prv'} . " < ". time . "\n", 1);
                $heartbeat->{'err'} = 1;
            } else {
                logMessage("Private Heartbeat is fine " . $heartbeat->{'prv'} . " > ". time . "\n", 4);
            }
            if (defined $heartbeat->{'err'} && $heartbeat->{'err'} == 1) {
                logMessage("Close connection with errors...\n", 1);
                $client->{'pub'}->close_now;
                $client->{'prv'}->close_now;
                $timer->stop;
                $pinger->stop;
                $loop->loop_stop;
            }
# Heartbeat is fine so you can handle streams data, send REST API requests, analyse and perform trading
        }
    );

    $pinger = IO::Async::Timer::Periodic->new(
        interval=> 20,
        on_tick => sub {
            foreach my $key ( keys %{ $client } ) {
                $req_id->{$key} ++;
                my $req_json = {
                    "req_id" => $req_id->{$key},
                    "op"     => "ping"
                };
                my $req = encode_json($req_json);
                logMessage("Sending ping msg: " . $req . "\n", 5);
                $client->{$key}->send_text_frame($req);
            }
        }
    );

    $client->{'pub'} = Net::Async::WebSocket::Client->new(
        on_text_frame => sub {
            my $data_pub = dataHandler(@_);
            if (defined $data_pub && defined $data_pub->{'op'} && $data_pub->{'op'} eq "ping" && $data_pub->{'success'}) {
                $heartbeat->{'pub'} = time+$heartbeat_interval;
            }
# Here you can put any stuff, include subs, analyse etc
        }
    );

    $client->{'prv'} = Net::Async::WebSocket::Client->new(
        on_text_frame => sub {
            my $data_prv = dataHandler(@_);
            if (defined $data_prv && defined $data_prv->{'op'} && $data_prv->{'op'} eq "pong") {
                $heartbeat->{'prv'} = time+$heartbeat_interval;
            }
# Here you can put any stuff, include subs, analyse etc
        }
    );

    $loop = IO::Async::Loop->new;

    $timer->start;
    $loop->add( $timer );

    $pinger->start;
    $loop->add( $pinger );

    $loop->add( $client->{'pub'} );
    $client->{'pub'}->connect(
       host => $host,
       service => $port,
       url => "wss://$host:$port/v5/public/spot",
    )->get;
    if (defined $api_key && defined $api_secret) {
        $loop->add( $client->{'prv'} );
        $client->{'prv'}->connect(
           host => $host,
           service => $port,
           url => "wss://$host:$port/v5/private",
        )->get;
    }
    logMessage("Connected, go ahead...\n", 3);
#################################
# Public subscription
#################################
    $req_id->{'pub'} ++;
    my $datasend = {
        "req_id" => $req_id->{'pub'},
        "op" => "subscribe",
        "args" => [
#            "tickers.BTCUSDT",
#            "tickers.ADAUSDT"
            "publicTrade.ADAUSDT"
        ]
    };
    $client->{'pub'}->send_text_frame( encode_json($datasend) );
#################################
# Private subscription
#################################
    if (defined $api_key && defined $api_secret) {
        logMessage("API Key/Secret defined. Attempting to send private request...\n", 3);
# auth
        $req_id->{'prv'} ++;
        my $expires = (time + 3) * 1000;
        my $signature = hmac_sha256_hex("GET/realtime$expires", $api_secret);
        my $datasend = {
            'req_id' => $req_id->{'prv'},
            'op' => 'auth',
            'args' => [
                "$api_key",
                $expires,
                "$signature"
            ]
        };
        $client->{'prv'}->send_text_frame(encode_json($datasend));
# Request
        $req_id->{'prv'} ++;
        my $datasend = {
            "req_id" => $req_id->{'prv'},
            "op" => "subscribe",
            "args" => [
                "wallet"
            ]
        };
        $client->{'prv'}->send_text_frame(encode_json($datasend));
    } else {
        logMessage("API Key/Secret not defined.\n", 3);
    }
#################################
# Start main loop
#################################
    $loop->run;
#################################
# Wait and Restart
#################################
    logMessage("Wait 10 seconds before reconnect.\n", 2);
    sleep 10;
    logMessage("Start again...\n", 2);
}
#################################
# Subroutines
#################################
sub dataHandler {
    my ( $self, $frame ) = @_;
    my $decoded = decode_json($frame);
    if (defined $decoded->{'topic'}) {
        given($decoded->{'topic'}) {
            when(/^tickers/) {
                printf ("%s %s %s %s\n",
                    strftime("%Y-%m-%d %H:%M:%S", localtime),
                    $decoded->{'data'}->{'symbol'},
                    $decoded->{'data'}->{'lastPrice'},
                    $decoded->{'data'}->{'highPrice24h'},
                    $decoded->{'data'}->{'lowPrice24h'},
                );
            }
            when(/^publicTrade/) {
                printf ("%s\n", strftime("%Y-%m-%d %H:%M:%S", localtime));
                foreach my $data ( @{ $decoded->{'data'} } ) {
                    printf ("\t %s %s %s %s\n",
                        $data->{'s'},
                        $data->{'S'},
                        $data->{'p'},
                        $data->{'v'},
                    );
                }
            }
            default {
                print Dumper $decoded;
            }
        }
        return $decoded;
    }
    if (defined $decoded->{'op'}) {
        given($decoded->{'op'}) {
            when(/ping/) {
                if ($decoded->{'success'}) {
                    logMessage("Pong frame for public channel received with success.\n", 4);
                } else {
                    logMessage("Pong frame for public channel received with no success.\n", 2);
                }
            }
            when(/pong/) {
                if ($decoded->{'args'}[0]) {
                    logMessage("Pong frame for private channel received with success.\n", 4);
                } else {
                    logMessage("Pong frame for private channel received with no success.\n", 2);
                }
            }
            when(/auth/) {
                if ($decoded->{'success'}) {
                    logMessage("Authenticated with success.\n", 3);
                } else {
                    logMessage("Authenticated with no success.\n", 2);
                }
            }
            when(/subscribe/) {
                if ($decoded->{'success'}) {
                    logMessage("Subscribed with success.\n", 3);
                } else {
                    logMessage("Subscribed with no success.\n", 2);
                }
            }
            default {
                print Dumper $decoded;
            }
        }
        return $decoded;
    }
    return undef;
}

sub logMessage {
    my $string = $_[0];
    my $severity = $_[1];
    my @message = ('FATAL','ERROR','WARN','INFO','DEBUG','TRACE');
    if (defined $severity && $severity >= 0 && $severity <= $loglevel) {
        print strftime("%Y-%m-%d %H:%M:%S ", localtime);
        print "\[$message[$severity]\] ";
        print $string;
    }
};
