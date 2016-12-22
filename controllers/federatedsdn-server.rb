#------------------------------------------------------------------------------#
# Copyright 2010-2015, OpenNebula Systems                                      #
#                                                                              #
# Licensed under the Apache License, Version 2.0 (the "License"); you may      #
# not use this file except in compliance with the License. You may obtain      #
# a copy of the License at                                                     #
#                                                                              #
# http://www.apache.org/licenses/LICENSE-2.0                                   #
#                                                                              #
# Unless required by applicable law or agreed to in writing, software          #
# distributed under the License is distributed on an "AS IS" BASIS,            #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
# See the License for the specific language governing permissions and          #
# limitations under the License.                                               #
#------------------------------------------------------------------------------#

require 'rubygems'
require 'sinatra'

FSDN_LOCATION = File.dirname __FILE__

FEDERATED_SDN_LOG = File.expand_path("../federatedsdn-server.log",FSDN_LOCATION)
FEDERATED_SDN_CONF= File.expand_path("../config/federatedsdn-server.conf",
                                        FSDN_LOCATION)
RUBY_LIB_LOCATION = File.expand_path("../lib", FSDN_LOCATION)
ADAPTERS_LOCATION = File.expand_path("../adaptors", FSDN_LOCATION)

$: << RUBY_LIB_LOCATION
$: << File.dirname(RUBY_LIB_LOCATION)

require 'models'
require 'parser'

require 'pp'

configure do

    fednetpool = FederatedSDN::FedNetPool.new()

    # Bootstrap DB if needed
    # Initialize DB with federated network collection
    if !fednetpool.exists?
        STDOUT.puts "Bootstraping DB"

        # Bootstrap Federated Network Pool
        fednetpool.bootstrap
        FederatedSDN::SitePool.new().bootstrap
        FederatedSDN::NetSegmentPool.new().bootstrap
        FederatedSDN::TenantPool.new().bootstrap
        FederatedSDN::DBVersioning::bootstrap

        FederatedSDN::DBVersioning::insert_db_version(FederatedSDN::VERSION,
                                                      FederatedSDN::VERSION_CODE)
    end

    version_codes = FederatedSDN::DBVersioning::get_version_codes

    if version_codes.empty? or
       version_codes.to_a[-1][:version_code].to_i < FederatedSDN::VERSION_CODE
        STDERR.puts "Version mismatch, upgrade required. \n"\
            "DB VERSION: #{version_codes.last||10000}\n" \
            "FederatedSDN VERSION: #{FederatedSDN::VERSION_CODE}\n" \
            "Run the 'federatedsdn-db' command"
        exit 1
    end

    set :bind, FederatedSDN::CONF[:host]
    set :port, FederatedSDN::CONF[:port]

    set :root_path, (FederatedSDN::CONF[:proxy_path]||'/')

    set :config, FederatedSDN::CONF
end

use Rack::Session::Pool, :key => 'federatedsdn'

helpers do
    def authorized?
        @auth ||=  Rack::Auth::Basic::Request.new(request.env)
        @username = @auth.credentials[0]
        pass  =FederatedSDN::TenantPool.new().get_password(@auth.credentials[0])
        pass == @auth.credentials[1]
    end

    def build_response(st, result)
        content_type :json
        status st
        body Parser.generate_body(result)
    end

    def is_admin
        FederatedSDN::TenantPool.new().is_admin(@username)
    end    
end

before do
    halt 401, "Credentials not valid" if !authorized?
end

after do
    STDERR.flush
    STDOUT.flush
end

############################ General Methods ###################################

###############################################################################
# General Get for all pools
###############################################################################

# Get whole resource pool (collection)
get '/fednet' do
    st, result = FederatedSDN::FedNetPool.new().get_pool(@username, is_admin)
    build_response(st, result)
end

# Get whole resource pool (collection) or single Federated Network
get '/fednet/:resource' do
    if params[:resource].match(/\A\d+\z/)
      st, result = FederatedSDN::FedNetPool.new().get_fednet(params[:resource],
                                                             @username,
                                                             is_admin)
    else
        case params[:resource]
            when 'site'
                st, result = FederatedSDN::SitePool.new().get
            when 'tenant'
                if is_admin
                    st, result = FederatedSDN::TenantPool.new().get_pool
                else
                    st     = 403
                    result = ["User not authorized to access tenant pool"]
                end
        end
    end
    build_response(st, result)
end


# Get individual resource
get '/fednet/:resource/:id' do
    case params[:resource]
        when 'site'
            st, result = FederatedSDN::SitePool.new().get(params[:id])              
        when 'tenant'
            if is_admin
                st, result = FederatedSDN::TenantPool.new().get_tenant(params[:id])
            else
                st     = 403
                result = ["User not authorized to access Tenant pool"]
            end               
    end
    build_response(st, result)
end

###############################################################################
# General Delete
###############################################################################

# Delete resource
delete '/fednet/:resource/:id' do
    if is_admin
        case params[:resource]
            when 'site'
                pool = FederatedSDN::SitePool.new()
            when 'tenant'
                pool = FederatedSDN::TenantPool.new()
        end
        st, result = pool.delete(params[:id])
    else
        st     = 403
        result = ["User not authorized to access #{params[:resource]} pool"]
    end
    build_response(st, result)
end

###################### Resource Specific Methods ###############################


###############################################################################
# Federated Network
###############################################################################

# Create a new federated network
post '/fednet' do
    # Add owner
    fednet_hash          = Parser.parse_body(request)
    fednet_hash["owner"] = @username
    st, result = FederatedSDN::FedNetPool.new().create(fednet_hash)
    build_response(st, result)
end

# Update federated network
put '/fednet/:id' do
    fednet_pool = FederatedSDN::FedNetPool.new()
    st, result  = fednet_pool.update(params[:id],
                                     @username,
                                     is_admin,
                                     Parser.parse_body(request))
    build_response(st, result)
end

# Delete federated Network
delete '/fednet/:id' do
    pool = FederatedSDN::FedNetPool.new()
    st, result = pool.delete(params[:id],
                             @username,
                             is_admin)
    build_response(st, result)
end

###############################################################################
# Site
###############################################################################

# Create a new site
post '/fednet/site' do
    if is_admin
        # Add owner
        site_hash  = Parser.parse_body(request)
        st, result = FederatedSDN::SitePool.new().create(site_hash)
    else
        st     = 403
        result = ["User not authorized to modify Site pool"]
    end
    build_response(st, result)
end

# Update site
put '/fednet/site/:id' do
    if is_admin
        site_pool   = FederatedSDN::SitePool.new()
        st, result  = site_pool.update(params[:id], Parser.parse_body(request))
    else
        st     = 403
        result = ["User not authorized to modify Site pool"]
    end
end


###############################################################################
# Network Segment
###############################################################################

get '/fednet/:fednet_id/:site_id/netsegment' do
    netsegment_pool = FederatedSDN::NetSegmentPool.new()
    st, result     = netsegment_pool.get_pool(params[:fednet_id],
                                          params[:site_id],
                                          @username, 
                                          is_admin)
    build_response(st, result)
end

get '/fednet/:fednet_id/:site_id/netsegment/:id' do
    netsegment_pool = FederatedSDN::NetSegmentPool.new()
    st, result      = netsegment_pool.get_netsegment(params[:fednet_id],
                                          params[:site_id],
                                          params[:id],
                                          @username, 
                                          is_admin)
    build_response(st, result)
end

# Create a new federated network
post '/fednet/:fednet_id/:site_id/netsegment' do
    # Add owner
    netsegment_hash          = Parser.parse_body(request)
    netsegment_hash["owner"] = @username     
    st, result = FederatedSDN::NetSegmentPool.new().create(params[:fednet_id],
                                                           params[:site_id],
                                                           @username, 
                                                           is_admin,
                                                           netsegment_hash)
    build_response(st, result)
end

# Update network segment
put '/fednet/:fednet_id/:site_id/netsegment/:id' do
    netsegment_pool = FederatedSDN::NetSegmentPool.new()
    st, result      = netsegment_pool.update(params[:fednet_id],
                                             params[:site_id],
                                             params[:id],
                                             @username, 
                                             is_admin,
                                             Parser.parse_body(request))
    build_response(st, result)
end

delete '/fednet/:fednet_id/:site_id/netsegment/:id' do
    netsegment_pool = FederatedSDN::NetSegmentPool.new()
    st, result      = netsegment_pool.delete(params[:fednet_id],
                                             params[:site_id],
                                             params[:id],
                                             @username, 
                                             is_admin)
    build_response(st, result)
end

###############################################################################
# Tenant
###############################################################################

# Create a new Tenant
post '/fednet/tenant' do
    if is_admin
        st, result = FederatedSDN::TenantPool.new().create(Parser.parse_body(request))
    else
        st     = 403
        result = ["User not authorized to access Tenant pool"]
    end

puts st
puts result

    build_response(st, result)
end

# Update Tenant
put '/fednet/tenant/:id' do
    if is_admin
        tenant_pool = FederatedSDN::TenantPool.new()
        st, result  = tenant_pool.update(params[:id], Parser.parse_body(request))
    else
        st     = 403
        result = ["User not authorized to access Tenant pool"]
    end
    build_response(st, result)
end
