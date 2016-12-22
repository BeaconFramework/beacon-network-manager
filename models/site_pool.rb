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

    class SitePool < Pool
        TABLE_NAME    = "site_table"
        RESOURCE_NAME = "Site"

        def initialize()
            @table = DB.from(TABLE_NAME)
        end

        def bootstrap
            DB.run "CREATE TABLE #{TABLE_NAME} "\
                        "(id integer primary key autoincrement,"\
                        " name varchar(255) UNIQUE,"\
                        " type varchar(255),"\
                        " cmp_endpoint varchar(255))"
        end

         # Needs at least name and cmp_endpoint
        def create(site_hash)
            # Validate hash
            if !site_hash["name"] ||
               !site_hash["cmp_endpoint"]
               return 500, ["Malformed creation request for network segment"]
            end

            max_oid = -1

            DB.fetch("SELECT MAX(id) FROM #{TABLE_NAME}") do |row|
                max_oid = row[:"MAX(id)"].to_i
            end

            site_hash["id"] = max_oid + 1

            begin
                new_id = @table.insert(site_hash)
                return 201, @table.filter(:id => new_id).first
            rescue Exception => e
                return 500, ["Server exception: #{e.message}"]
            end
        end
    end
end
