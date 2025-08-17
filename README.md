# bybit-wss-api-pl

This is the basic method getting data from bybit wss


## Installation

### 1. Required software:

```
sudo dnf/apt/pkg install perl cpanminus screen git
```

### 2. Perl modules:

```
cpanm App::cpanoutdated
cpan-outdated -p | cpanm --sudo
cpanm IO::Async::Loop Net::Async::WebSocket::Client IO::Async::Timer::Periodic JSON POSIX Data::Dumper Digest::SHA --sudo
```

### 3. Downloading binance-bot
```
git clone https://github.com/dream-hunter/bybit-wss-api-pl.git
```

## Start Application

### 1.Public-only stream:

```
cd bybit-wss-api-pl
/usr/bin/env perl bybit-wss.pl
```

### 2. With API key and private-stream

```
cd bybit-wss-api-pl
/usr/bin/env perl bybit-wss.pl <API_KEY> <API_SECRET>
```

Of course firstly you have to generate API Key in "Account"->"API" section on Bybit web-site

API Docs: https://bybit-exchange.github.io/docs/v5/ws/connect

Enjoy!

# Funding

USDT(ERC20) 0xa43d3a2796285842c2496bf9aef5796f1c832cb5

BTC(BTC)    13jSSBQjNzYkGNsiZniXr7hYtW24DFQR8h

ETH(ERC20)  0xa43d3a2796285842c2496bf9aef5796f1c832cb5

# Changelog

2025-08-11 - Project created

2025-08-17 - Added loglevel and severity feature