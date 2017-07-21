
# Beacon Network Manager

## Description

Beacon Network Manager (BeaconNM) is the software component that allows to build 
a Federated Network by aggregating two or more Federated Network Segments. 
It features an API to allow for Federated Network definitions, and uses adapters 
to talk to the federation agents APIs in different cloud infrastructures 
as well as to the Cloud Management Platform.

## Installation

### Ruby Libraries Requirements

A gemfile is provided to install ruby libraries. In order to use it, 
you need to install bundler first:

$ sudo gem install bundle

And afterwards invoke the install command:

$ bundle install

## Server Execution

The server can be invoked using the bin/federatedsdn-server script. Before the 
first execution check config/federatedsdn-server.conf to adjust configuration.

$ cd bin && ./federatedsdn-server start

And stopped:

$ cd bin && ./federatedsdn-server stop

## Client Tools

The Beacon Network Manager comes with a set of client tools to invoke operations
over the different resources. 

They need the Beacon Network Manager server and a valid username and password. The
defaults are:

:root_username: "root"
:root_password: "beaconnm"

The different client tools are

- client/bin/fsdn-fednet
- client/bin/fsdn-netseg
- client/bin/fsdn-site
- client/bin/fsdn-tenant
