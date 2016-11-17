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
    class Pool
        def empty?
            @table.empty?
        end

        def exists?
            begin
              empty?
              return false
            rescue Exception => e
              return true
            end
        end

       # Get the whole pool or individual resource
        def get(id=nil)
            if !id
                begin
                    return 201, @table.to_a
                rescue Exception => e
                    return 500, [e.message]
                end
            else
                begin
                    return 201, @table.filter(:id => id).first
                rescue Exception => e
                    return 500, [e.message]
                end
            end
        end

        # Update an individual resource
        def update(id, new_resource)
            begin
                @table.filter(:id => id).update(new_resource)
                return 201, ["Resource #{id} updated."]
            rescue Exception => e
                return 500, [e.message]
            end
        end

        # Delete an individual resource
        def delete(id)
            begin
                @table.filter(:id => id).delete
                return 201, ["Resource #{id} removed."]
            rescue Exception => e
                return 500, [e.message]
            end
        end
    end
end
