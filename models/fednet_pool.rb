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

module FederatedSDN

    class FedNetPool < Pool
        TABLE_NAME    = "fednet_table"
        RESOURCE_NAME = "Federated Network"

        def initialize()
            @table = DB.from(TABLE_NAME)
        end

        def bootstrap
            DB.run "CREATE TABLE #{TABLE_NAME} "\
                        "(id integer primary key autoincrement, "\
                        "owner varchar(255),"\
                        "name varchar(255) UNIQUE,"\
                        "status varchar(255),"\
                        "linktype varchar(255),"\
                        "topology varchar(255),"\
                        "type varchar(255))"
        end

        # Needs at least name, linktype and type
        def create(fednet_hash)
            # Validate hash
            if !fednet_hash["name"] ||
               !fednet_hash["type"] ||
               !fednet_hash["linktype"]
               return 500, "Malformed creation request for #{RESOURCE_NAME}"
            end

            fednet_hash["topology"] = "" if !fednet_hash["topology"]
            fednet_hash["status"]   = "unlinked"

            max_oid = -1

            DB.fetch("SELECT MAX(id) FROM #{TABLE_NAME}") do |row|
                max_oid = row[:"MAX(id)"].to_i
            end

            fednet_hash["id"] = max_oid + 1

            begin
                new_id = @table.insert(fednet_hash)
                return 201, @table.filter(:id => new_id).first
            rescue Exception => e
                return 500, ["Server exception: #{e.message}"]
            end
        end

       # Get the whole pool if admin, or all owned resources
        def get_pool(username, is_admin)
            begin
                if is_admin
                    return 201, @table.to_a
                else    
                    return 201, @table.filter(:owner => username).to_a
                end
            rescue Exception => e
                return 500, [e.message]
            end
        end

       # Get an individual fednet
        def get_fednet(id, username, is_admin)
            begin
                if is_admin
                    fednet_hash = @table.filter(:id => id).first
                    fednet_hash[:netsegments] = FederatedSDN::NetSegmentPool.new().get_netsegments_in_fednet(id, username)
                    return 201, fednet_hash
                else
                    fednet_hash = @table.filter(:id => id).first
                    if fednet_hash[:owner] == username
                        # add all the netsegments
                        fednet_hash[:netsegments] = FederatedSDN::NetSegmentPool.new().get_netsegments_in_fednet(id, username)
                        return 201, fednet_hash
                    else
                        return 403, ["Access to #{RESOURCE_NAME} #{id} is not allowed"]
                    end
                end
            rescue Exception => e
                return 500, [e.message]
            end
        end

        # Update a fednet
        def update(id, username, is_admin, new_fednet)
            new_resource = new_fednet
            begin
                if new_resource["status"] == "link"
                    @is_opennebula = false
                    @is_openstack  = false
                    # Call link adapter to create the fednet at the FA level

                    # Get all the netsegments
                    fednet_hash = @table.filter(:id => id).first
                    fednet_hash[:netsegments] = FederatedSDN::NetSegmentPool.new().get_netsegments_in_fednet(id, username)
                    # Build the token Array
                    token = ""

                    # Get all the FAs 
                    fa_array = Array.new
                    fednet_hash[:netsegments].each{|ns|
                        fa_array << ns[:fa_endpoint]
                    }

                    # Build the network table
                    net_array = Array.new
                    fednet_hash[:netsegments].each{|ns|
                        net_array_element             = Hash.new
                        net_array_element[:name]      = ns[:name]
                        net_array_element[:vnid]      = ns[:cmp_net_id]
                        net_array_element[:site]      = FederatedSDN::SitePool.new().get(ns[:site_id])[1][:name]
                        net_array_element[:tenant_id] = FederatedSDN::TenantPool.new().get_tenant_id_in_site(username, FederatedSDN::SitePool.new().get(ns[:site_id])[1][:id])
                        net_array_element[:cmp_blob]  = ns[:cmp_blob]
                        
                        net_array << net_array_element

                        if FederatedSDN::SitePool.new().get(ns[:site_id])[1][:type] == "opennebula"
                            @is_opennebula = true
                        end


                        if FederatedSDN::SitePool.new().get(ns[:site_id])[1][:type] == "openstack"
                            @is_openstack = true
                        end
                    }

                    resultcode = 0

                    if @is_openstack
                        result = link("openstack",
                                      fednet_hash[:linktype],
                                      token,
                                      fa_array,
                                      net_array)
                        resultcode = result.code
                    elsif @is_opennebula
                        result = link("opennebula",
                                      fednet_hash[:linktype],
                                      token,
                                      fa_array,
                                      net_array)
                        resultcode = result.code
                    end

                    if resultcode == 0
                        new_resource["status"] = "linked"
                    else
                       return 500, 
                           ["Couldn't perform link operation. "\
                            "Message from driver:"\
                            " #{result.stdout}"]
                    end
                end

                # Update the DB
                if is_admin
                    @table.filter(:id => id).update(new_resource)
                    return 201, ["#{RESOURCE_NAME} #{id} updated."]
                else
                    fednet_hash = @table.filter(:id => id).first
                    if fednet_hash[:owner] == username
                        @table.filter(:id => id).update(new_resource)
                        return 201, @table.filter(:id => id).first
                    else
                        return 403, ["Updating #{RESOURCE_NAME} #{id} is not allowed"]
                    end
                end
            rescue Exception => e
                return 500, [e.message]
            end
        end

        # Delete a fednet
        def delete(id, username, is_admin)
            begin
                fednet_ds = @table.filter(:id => id)

                if fednet_ds.empty?
                    return 404, ["#{RESOURCE_NAME} #{id} not found."]
                end

                if is_admin
                    fednet_ds.delete
                    return 201, ["#{RESOURCE_NAME} #{id} removed."]
                else
                    fednet_hash = fednet_ds.first
                    if fednet_hash[:owner] == username
                        fednet_hash.delete
                        return 201,  ["#{RESOURCE_NAME} #{id} removed."]
                    else
                        return 403, ["Deleting #{RESOURCE_NAME} #{id} is not allowed"]
                    end
                end
            rescue Exception => e
                return 500, [e.message]
            end
        end       

        # Check if the table exists
        def exists?
            DB.table_exists?(TABLE_NAME)
        end

        def link(site_type, type, token, fa_endpoints, network_table)
            cmd = ADAPTERS_LOCATION + "/" + site_type.downcase + "/"
            cmd = cmd + "link"


            stdin_hash = {:type          => type,
                          :token         => token,
                          :fa_endpoints  => fa_endpoints,
                          :network_table => network_table}

            stdin_base64 = Base64.encode64(JSON.pretty_generate(stdin_hash)).gsub("\n","")

            LocalCommand.run(cmd, stdin_base64)
        end
    end
end

