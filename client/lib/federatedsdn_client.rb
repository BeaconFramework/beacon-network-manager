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

require 'uri'
require 'net/https'

require 'federatedsdn_version'

module FederatedSDN
    class Client
        def initialize(username, password, url, user_agent="Ruby")
            @username = username || ENV['FEDSDN_USER']
            @password = password || ENV['FEDSDN_PASSWORD']

            if !@username or !@password
                STDERR.puts "No username or password defined"
                exit
            end

            url = url || ENV['FEDSDN_URL'] || 'http://localhost:6121/'
            @uri = URI.parse(url)

            @user_agent = "FederatedSDN #{FederatedSDN::VERSION} (#{user_agent})"

            @host = nil
            @port = nil

            if ENV['http_proxy']
                uri_proxy  = URI.parse(ENV['http_proxy'])
                @host = uri_proxy.host
                @port = uri_proxy.port
            end
        end

        # Federated Networks CRUD operations

        def create_fednet(body)
            post("/fednet", body)
        end

        def get_fednets
            get("/fednet")
        end

        def get_fednet(fednet_id)
            get("/fednet/" + fednet_id)
        end

        def update_fednet(fednet_id, body)
            put("/fednet/" + fednet_id, body)
        end

        def delete_fednet(fednet_id)
            delete("/fednet/" + fednet_id)
        end

        # Site CRUD operations

        def create_site(body)
            post("/fednet/site", body)
        end

        def get_sites
            get("/fednet/site")
        end

        def get_site(site_id)
            get("/fednet/site/" + site_id)
        end

        def update_site(site_id, body)
            put("/fednet/site/" + site_id, body)
        end

        def delete_site(site_id)
            delete("/fednet/site/" + site_id)
        end

        # Network Segment CRUD operations

        def create_netsegment(fednet_id, site_id, body)
            post("/fednet/#{fednet_id}/#{site_id}/netsegment", body)
        end

        def get_netsegments(fednet_id, site_id)
            get("/fednet/#{fednet_id}/#{site_id}/netsegment")
        end

        def get_netsegment(fednet_id, site_id, netsegment_id)
            get("/fednet/#{fednet_id}/#{site_id}/netsegment/"+ netsegment_id)
        end

        def update_netsegment(fednet_id, site_id, netsegment_id, body)
            put("/fednet/#{fednet_id}/#{site_id}/netsegment/" + netsegment_id, body)
        end

        def delete_netsegment(fednet_id, site_id, netsegment_id)
            delete("/fednet/#{fednet_id}/#{site_id}/netsegment/" + netsegment_id)
        end

        # Tenant CRUD operations

        def create_tenant(body)
            post("/fednet/tenant", body)
        end

        def get_tenants
            get("/fednet/tenant")
        end

        def get_tenant(tenant_id)
            get("/fednet/tenant/" + tenant_id)
        end

        def update_tenant(tenant_id, body)
            put("/fednet/tenant/" + tenant_id, body)
        end

        def delete_tenant(tenant_id)
            delete("/fednet/tenant/" + tenant_id)
        end        

    private

        def get(path)
            req = Net::HTTP::Proxy(@host, @port)::Get.new(path)

            do_request(req)
        end

        def delete(path)
            req = Net::HTTP::Proxy(@host, @port)::Delete.new(path)

            do_request(req)
        end

        def post(path, body)
            req = Net::HTTP::Proxy(@host, @port)::Post.new(path)
            req.body = body

            do_request(req)
        end

        def put(path, body)
            req = Net::HTTP::Proxy(@host, @port)::Put.new(path)
            req.body = body

            do_request(req)
        end

        def do_request(req)
            if @username && @password
                req.basic_auth @username, @password
            end

            req['User-Agent'] = @user_agent

            res = FederatedSDN::Client::http_start(@uri, @timeout) do |http|
                http.request(req)
            end

            res
        end

        # #########################################################################
        # Starts an http connection and calls the block provided. SSL flag
        # is set if needed.
        # #########################################################################
        def self.http_start(url, timeout, &block)
            host = nil
            port = nil

            if ENV['http_proxy']
                uri_proxy  = URI.parse(ENV['http_proxy'])
                host = uri_proxy.host
                port = uri_proxy.port
            end

            http = Net::HTTP::Proxy(host, port).new(url.host, url.port)

            if timeout
                http.read_timeout = timeout.to_i
            end

            if url.scheme=='https'
                http.use_ssl = true
                http.verify_mode=OpenSSL::SSL::VERIFY_NONE
            end

            begin
                res = http.start do |connection|
                    block.call(connection)
                end
            rescue Errno::ECONNREFUSED => e
                str =  "Error connecting to server (#{e.to_s}).\n"
                str << "Server: #{url.host}:#{url.port}"

                return FederatedSDN::Error.new(str,"503")
            rescue Errno::ETIMEDOUT => e
                str =  "Error timeout connecting to server (#{e.to_s}).\n"
                str << "Server: #{url.host}:#{url.port}"

                return FederatedSDN::Error.new(str,"504")
            rescue Timeout::Error => e
                str =  "Error timeout while connected to server (#{e.to_s}).\n"
                str << "Server: #{url.host}:#{url.port}"

                return FederatedSDN::Error.new(str,"504")
            rescue SocketError => e
                str =  "Error timeout while connected to server (#{e.to_s}).\n"

                return FederatedSDN::Error.new(str,"503")
            rescue
                return FederatedSDN::Error.new($!.to_s,"503")
            end

            if res.is_a?(Net::HTTPSuccess)
                res
            else
                FederatedSDN::Error.new(res.body, res.code)
            end
        end
    end


    # #########################################################################
    # The Error Class represents a generic error in the Cloud Client
    # library. It contains a readable representation of the error.
    # #########################################################################
    class Error
        attr_reader :message
        attr_reader :code

        # +message+ a description of the error
        def initialize(message=nil, code="500")
            @message=message
            @code=code
        end

        def to_s()
            @message
        end
    end

    # #########################################################################
    # Returns true if the object returned by a method of the OpenNebula
    # library is an Error
    # #########################################################################
    def self.is_error?(value)
        value.class==FederatedSDN::Error
    end
end
