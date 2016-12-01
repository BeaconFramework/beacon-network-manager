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

    class NetSegmentPool < Pool
        TABLE_NAME    = "netsegment_table"
        RESOURCE_NAME = "Network Segment"

        def initialize()
            @table = DB.from(TABLE_NAME)
        end

        def bootstrap
            DB.run "CREATE TABLE #{TABLE_NAME} "\
                            "(id integer primary key autoincrement,"\
                            " owner varchar(255),"\
                            " name varchar(255),"\
                            " fa_endpoint varchar(255),"\
                            " network_address varchar(255),"\
                            " network_mask varchar(255),"\
                            " size varchar(255),"\
                            " vlan_id varchar(255),"\
                            " cmp_net_id varchar(255),"\
                            " cmp_blob MEDIUMTEXT,"\
                            " fednet_id REFERENCES fednet_table(id),"\
                            " site_id REFERENCES site_table(id))"
        end

        # Needs at least fa_endpoint, fednet_id and site_id
        def create(fednet_id, site_id, username, is_admin, netsegment_hash)
            # Check permissions over all objects
            if !is_admin
                is_site_valid=FederatedSDN::TenantPool.new().is_site_valid(username,
                                                                     site_id)
                if !is_site_valid
                    return 403, ["Access to Site #{site_id} is not allowed"]
                end

                st, fednet_ds =FederatedSDN::FedNetPool.new().get_fednet(fednet_id, 
                                                                    username, 
                                                                    is_admin)

                if st != 201 or fednet_ds[:owner] != username
                    return 403, ["Access to Federated Network #{fednet_id} is not allowed"]
                end
            end

            # Validate hash
            if !netsegment_hash["fa_endpoint"] ||
               !netsegment_hash["name"]
               return 500, ["Malformed creation request for #{RESOURCE_NAME}"]
            end

            max_oid = -1

            DB.fetch("SELECT MAX(id) FROM #{TABLE_NAME}") do |row|
                max_oid = row[:"MAX(id)"].to_i
            end

            netsegment_hash["id"]        = max_oid + 1
            netsegment_hash["fednet_id"] = fednet_id
            netsegment_hash["site_id"]   = site_id

            ## Call the add_networksegment driver
            # First, get all the needed info
            #  Get the site
            st, site_ds = FederatedSDN::SitePool.new().get(site_id)
            if st !=201
                return 500, ["Cannot get site information. Does site"\
                            " with id #{site_id} exist?"]
            end

            tenant_in_site_ds = FederatedSDN::TenantPool.new().get_tenant_info(username,
                                                           site_id)

            if !tenant_in_site_ds
                return 404, ["Tenant #{username} not valid in site #{site_id}"]
            end

            site_type          = site_ds[:type]
            cmp_endpoint       = site_ds[:cmp_endpoint]
            network_segment_id = netsegment_hash["cmp_net_id"]

            if site_type.downcase == "opennebula"
                token = tenant_in_site_ds[:credentials]
            else
                token = tenant_in_site_ds[:token]
            end

            result =  add_networksegment(site_type,
                                         network_segment_id,
                                         cmp_endpoint,
                                         token)

            if result.code == 0
                result = JSON.parse(Base64.decode64(result.stdout))
                netsegment_hash["cmp_blob"] = result["network_info"].to_s
            else
               return 500, 
                   ["Cannot get network information for network "\
                    "#{network_segment_id} on site #{site_id}. "\
                    "Message from driver:"\
                    " #{result.stdout}"]
            end

            begin
                new_id = @table.insert(netsegment_hash)
                return 201, @table.filter(:id => new_id).first
            rescue Exception => e
                return 500, ["Server exception: #{e.message}"]
            end
        end

        # Get  all defined segments for a fed network and site per user 
        # or all if admin user
        def get_pool(fednet_id, site_id, username, is_admin)
            fednet_fltr = {:fednet_id => fednet_id}
            site_fltr   = {:site_id => site_id}

            begin
                if is_admin
                  return 201,
                         @table.filter(fednet_fltr).filter(site_fltr).to_a
                else
                  return 201, 
                         @table.filter(fednet_fltr).filter(site_fltr).filter(:owner => username).to_a
                end
            rescue Exception => e
                return 500, [e.message]
            end
        end

        # Get an individual network segment
        def get_netsegment(fednet_id, site_id, id, username, is_admin)
            id_fltr     = {:id => id}
            fednet_fltr = {:fednet_id => fednet_id}
            site_fltr   = {:site_id => site_id}

            begin
                if is_admin
                    return 201, @table.filter(id_fltr).filter(fednet_fltr).filter(site_fltr).first
                else
                    netsegment_hash = @table.filter(id_fltr).filter(fednet_fltr).filter(site_fltr).first
                    if netsegment_hash[:owner] == username
                        return 201, netsegment_hash
                    else
                        return 403, ["Access to #{RESOURCE_NAME} #{id} is not allowed"]
                    end
                end
            rescue Exception => e
                return 500, [e.message]
            end
        end

        # Get all network segments for a particular fednet
        def get_netsegments_in_fednet(fednet_id, username)
            fednet_fltr = {:fednet_id => fednet_id}
            @table.filter(fednet_fltr).filter(:owner => username).to_a
        end


        # Update a particular network segment resource
        def update(fednet_id, site_id, id,  username, is_admin, new_netsegment)
            id_f     = {:id => id}
            fednet_f = {:fednet_id => fednet_id}
            site_f   = {:site_id => site_id}

            if is_admin
                @table.filter(id_f).filter(fednet_f).filter(site_f).update(new_netsegment)
                return 201, ["#{RESOURCE_NAME} #{id} updated."]
            else
                netsegment_hash = @table.filter(id_f).filter(fednet_f).filter(site_f).first
                if netsegment_hash[:owner] == username
                    return 201, netsegment_hash.update(new_resource)
                else
                    return 403, ["Updating #{RESOURCE_NAME} #{id} is not allowed"]
                end
            end      
        end

        # Delete an individual network_segment
        def delete(fednet_id, site_id, id, username, is_admin)
            id_f     = {:id => id}
            fednet_f = {:fednet_id => fednet_id}
            site_f   = {:site_id => site_id}
            begin
                netseg = @table.filter(id_f).filter(fednet_f).filter(site_f)

                if netseg.empty?
                    return 404, ["#{RESOURCE_NAME} #{id} not found."]
                end

                if is_admin
                    netseg.delete
                    return 201, ["#{RESOURCE_NAME} #{id} removed."]
                else
                    fednet_hash = netseg.first
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

        # Call the networksegment driver
        def add_networksegment(site_type, network_segment_id, cmp_endpoint, token)
            cmd = ADAPTERS_LOCATION + "/" + site_type.downcase + "/"
            cmd = cmd + "add_networksegment"

            stdin_hash = {:network_segment_id => network_segment_id,
                          :cmp_endpoint       => cmp_endpoint,
                          :token              => token}

            stdin_base64 = Base64.encode64(JSON.pretty_generate(stdin_hash))

            LocalCommand.run(cmd, stdin_base64)
        end

    end
end

