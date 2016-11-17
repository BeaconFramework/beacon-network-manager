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
require 'yaml'
require 'sequel'
require 'command_manager'
require 'federatedsdn_version'
require 'base64'

module FederatedSDN
    DB_NAME = 'federatedsdn'

    begin
        CONF = YAML.load_file(FEDERATED_SDN_CONF)
    rescue Exception => e
        STDERR.puts "Error parsing config file #{FEDERATED_SDN_CONF}:"\
                    " #{e.message}"
        exit 1
    end

    begin
        DB = Sequel.sqlite(CONF[:db_filename])
    rescue Exception => e
        raise "Error connecting to DB: " + e.message
    end

    module DBVersioning
        DB_VERSIONING_TABLE = 'db_versioning'

        def self.bootstrap
            DB.run "CREATE TABLE #{DB_VERSIONING_TABLE} "\
                "(version varchar(255),"\
                " version_code varchar(255),"\
                " timestamp varchar(255))"
        end

        def self.insert_db_version(version, version_code)
            DB.from(DB_VERSIONING_TABLE).insert({
                :version => version,
                :version_code => version_code,
                :timestamp => Time.now.to_i})
        end

        def self.get_version_codes
            DB.from(DB_VERSIONING_TABLE)
        end

        def self.exists_versioning_table
            DB.table_exists?(DB_VERSIONING_TABLE)
        end
    end
end
