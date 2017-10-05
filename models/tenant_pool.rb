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

    class TenantPool < Pool
        RESOURCE_NAME              = "Tenant"
        TABLE_NAME                 = "tenant_table"
        TENANT_TO_SITE_TABLE_NAME  = "tenant_to_site_user_id"

        def initialize()
            @table         = DB.from(TABLE_NAME)
            @table_to_site = DB.from(TENANT_TO_SITE_TABLE_NAME)
        end

        def bootstrap
            DB.run "CREATE TABLE #{TABLE_NAME} "\
                        "(id integer primary key autoincrement,"\
                        " name varchar(255) UNIQUE,"\
                        " password varchar(255),"\
                        " type varchar(255))"

            DB.run "CREATE TABLE tenant_to_site_user_id "\
                        "(tenant_id integer REFERENCES #{TABLE_NAME}(id),"\
                        " site_id integer REFERENCES site_table(id),"\
                        " user_id_in_site varchar(255),"\
                        " credentials varchar(255),"\
                        " token varchar(255))"

            # Add root admin user
            username = FederatedSDN::CONF[:root_username]
            password = FederatedSDN::CONF[:root_password]
            id       = 1

            tenant_hash = {
                :id => id,
                :name => username,
                :password => password,
                :type => "admin"
            }

            @table.insert(tenant_hash)
        end

        # Needs at least name and password for Federated SDN auth
        def create(tenant_hash)
            # Validate hash
            if !tenant_hash["name"] ||
               !tenant_hash["password"]
               return 500, ["Malformed creation request for tenant"]
            end

            max_oid = -1

            DB.fetch("SELECT MAX(id) FROM #{TABLE_NAME}") do |row|
                max_oid = row[:"MAX(id)"].to_i
            end

            tenant_hash["id"] = max_oid + 1   
            valid_sites       = tenant_hash["valid_sites"]
            tenant_hash.delete("valid_sites")

            begin
                new_id = @table.insert(tenant_hash)
            rescue Exception => e
                return 500, [e.message]
            end

            if valid_sites
                valid_sites.each{|site_hash|
                    if !site_hash["site_id"] ||
                       !site_hash["credentials"] 
                     return 500, 
                            ["Site description malformed, tenant creation failed"]
                    end

                    # Call to validate_user
                    st, site_ds = FederatedSDN::SitePool.new().get(site_hash["site_id"])

                    if st !=201
                        return 500, "Cannot get site information. Does site"\
                                    " with id #{site_hash['site_id']} exist?"
                    end

                    # Call to validate_user
                    site_type    = site_ds[:type]
                    cmd_endpoint = site_ds[:cmp_endpoint]
                    username     = site_hash["credentials"].split(":")[0]
                    password     = site_hash["credentials"].split(":")[1]

                    result = validate_user(site_type,
                                           cmd_endpoint,
                                           username,
                                           password)

                    validate_sucess = false

                    if result.code == 0
                        result = JSON.parse(Base64.decode64(result.stdout))
                        if result["returncode"] == 0
                            validate_sucess              = true
                            site_hash["token"]           = result["token"]
                            site_hash["user_id_in_site"] = result["tenant_id"]
                        else
                            return 401, 
                               ["Invalid tenant credentials for site "\
                                "#{site_hash['site_id']}. Message from driver:"\
                                " #{result['errormsg']}"]
                        end
                    end
     
                    site_hash["tenant_id"] = new_id

                    if validate_sucess
                        begin
                            site_hash["site_id"] = site_hash["site_id"].to_i
                            @table_to_site.insert(site_hash)
                        rescue Exception => e
                            return 500, [e.message + 
                                         ". \nCheck all sites exist."]
                        end
                    else
                        return 401, 
                           ["Error checking tenant credentials for site "\
                           "#{site_hash['site_id']}"]
                    end
                }
            end

            main_info = @table.filter(:id => new_id).first
            main_info["valid_sites"] = @table_to_site.filter(:tenant_id => new_id).to_a

            return 201, main_info
        end

        def get_tenant(id)
            begin
                main_info = @table.filter(:id => id).first
                main_info["valid_sites"] = @table_to_site.filter(:tenant_id => id).to_a
                return 201, main_info
            rescue Exception => e
                return 500, [e.message]
            end
        end

        def get_pool
            begin
                return 201, @table.to_a
            rescue Exception => e
                return 500, [e.message]
            end
        end

        def update(tenant_id, new_tenant)
            # Clear the sites for tenant table 
            @table_to_site.filter({:tenant_id => tenant_id}).delete

            if new_tenant["valid_sites"]
                new_tenant["valid_sites"].each{|site_hash|

                    if !site_hash["site_id"] ||
                       !site_hash["user_id_in_site"] ||
                       !site_hash["credentials"] 
                     return 500, 
                            "Site info malformed request for tenant update"
                    end

                    st, site_ds = FederatedSDN::SitePool.new().get(site_hash["site_id"])

                    if st !=201
                        return 500, "Cannot get site information. Does site"\
                                    " with id #{site_hash['site_id']} exist?"
                    end

                    # Call to validate_user
                    site_type    = site_ds[:type]
                    cmd_endpoint = site_ds[:cmp_endpoint]
                    username     = site_hash["credentials"].split(":")[0]
                    password     = site_hash["credentials"].split(":")[1]

                    result = validate_user(site_type,
                                           cmd_endpoint,
                                           username,
                                           password)

                    validate_sucess = false

                    if result.code == 0
                        result = JSON.parse(Base64.decode64(result.stdout))
                        if result["returncode"] == 0
                            validate_sucess              = true
                            site_hash["token"]           = result["token"]
                            site_hash["user_id_in_site"] = result["tenant_id"]
                        else
                            return 401, 
                               ["Error checking tenant credentials for site "\
                               "#{site_hash['site_id']}"]
                        end
                    end

                    site_hash["tenant_id"] = tenant_id

                    if validate_sucess
                        begin
                            site_hash["site_id"] = site_hash["site_id"].to_i
                            @table_to_site.insert(site_hash)
                        rescue Exception => e
                            return 500, [e.message + 
                                         ". \nCheck all sites exist."]
                        end
                    else
                        return 401,
                               ["Invalid tenant credentials for site "\
                                "#{site_hash['site_id']}. Message from driver:"\
                                " #{result['errormesg']}"]
                    end

                }
            end

            new_tenant.delete("valid_sites")

            begin
                @table.filter({:id => tenant_id}).update(new_tenant)
                return 201, ["#{RESOURCE_NAME} #{tenant_id} updated."]
            rescue Exception => e
                return 500, [e.message]
            end
        end

        def delete(tenant_id)
            begin
                tenant_ds = @table.filter({:id => tenant_id})

                if !tenant_ds.empty?
                    @table_to_site.filter({:tenant_id => tenant_id}).delete
                    tenant_ds.delete
                    return 201, ["#{RESOURCE_NAME} #{tenant_id} deleted."]
                else
                    return 404, ["#{RESOURCE_NAME} #{tenant_id} not found."]
                end
            rescue Exception => e
                return 500, [e.message]
            end 

        end 

        def get_password(username)
            @table.filter(:name => username).first[:password]
        end

        def get_tenant_info(username, site_id)
            tenant_id = @table.filter(:name => username).first[:id]
            @table_to_site.filter({:tenant_id => tenant_id}).filter({:site_id => site_id}).first
        end

        def is_site_valid(username, site_id)
            tenant_id=@table.filter(:name => username).first[:id]
            !@table_to_site.filter({:tenant_id => tenant_id}).filter({:site_id => site_id}).empty?
        end

        def is_admin(username)
             @table.filter(:name => username).first[:type] == "admin"
        end

        def get_tenant_id_in_site(username, site)
             tenant_id = @table.filter(:name => username).first[:id]
             @table_to_site.filter(:tenant_id => tenant_id).filter(:site_id => site).first[:user_id_in_site]
        end

        def get_tenant_token(username, site)
             tenant_id = @table.filter(:name => username).first[:id]
             @table_to_site.filter(:tenant_id => tenant_id).filter(:site_id => site).first[:token]
        end

        def validate_user(site_type, cmp_endpoint, username, password)
            cmd = ADAPTERS_LOCATION + "/" + site_type.downcase + "/"
            cmd = cmd + "validate_user"

            stdin_hash = {:username => username,
                          :password => password,
                          :cmp_endpoint => cmp_endpoint}

            stdin_base64 = Base64.encode64(JSON.pretty_generate(stdin_hash)).gsub("\n","")

            LocalCommand.run(cmd, stdin_base64)
        end
    end
end