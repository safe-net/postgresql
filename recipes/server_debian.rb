#
# Cookbook Name:: postgresql
# Recipe:: server
#
# Author:: Joshua Timberman (<joshua@opscode.com>)
# Author:: Lamont Granquist (<lamont@opscode.com>)#
# Copyright 2009-2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "postgresql::client"
include_recipe "postgresql::set_data_directory"

case node[:postgresql][:version]
when "8.3"
  node.default[:postgresql][:ssl] = "off"
else # > 8.3
  node.default[:postgresql][:ssl] = "true"
end

node['postgresql']['server']['packages'].each do |pg_pack|
  package pg_pack do
    action :install
  end
end

service "postgresql" do
  case node['platform']
  when "ubuntu"
    case
    when node['platform_version'].to_f <= 10.04
      service_name "postgresql-#{node['postgresql']['version']}"
    else
      service_name "postgresql"
    end
  when "debian"
    case
    when node['platform_version'].to_f <= 5.0
      service_name "postgresql-#{node['postgresql']['version']}"
    else
      service_name "postgresql"
    end
  end
  supports :restart => true, :status => false, :reload => true
  pattern "bin/postgres "
  action :nothing
end

current_data_directory = nil
moving_data_directory = false

ruby_block "get current data directory" do
  block do
    begin
      IO.foreach("/etc/postgresql/9.1/main/postgresql.conf") { |line|
        Chef::Log.info("Checking line: #{line}")
        if line =~ /data_directory\s*=\s*'(.*?)'/
          Chef::Log.info("Found the line!!")
          current_data_directory = $~[1]
          raise StopIteration
        end
      }
    rescue StopIteration
    end
    if !current_data_directory || !File.directory?(current_data_directory)
      Chef::Log.fatal("could not determine current data directory: #{current_data_directory}")
    end
    moving_data_directory = !File.exists?("#{node.postgresql.server.data_directory}/PG_VERSION")
    Chef::Log.info("Value of moving (first): #{moving_data_directory}")
    moving_data_directory ||= current_data_directory != node.postgresql.server.data_directory
    Chef::Log.info("Value of data_directory attribute: " + node.postgresql.server.data_directory)
    Chef::Log.info("Value of current_data_directory: #{current_data_directory}")
    Chef::Log.info("Value of moving: #{moving_data_directory}")
  end
end



  # data directory attribute is set to something other than the default installed by the postgres package
  # stop the server, move the database, start the server

# if moving_data_directory

  directory "#{node.postgresql.server.data_directory}" do
    owner "postgres"
    group "postgres"
    mode 0700
    recursive true
    only_if {moving_data_directory}
  end

# empty ruby block resource hack to notify service resource based on another condition
ruby_block "stop postgres service" do
  block {}
  notifies :stop, resources("service[postgresql]"), :immediately
  only_if {moving_data_directory}
end

ruby_block "move db" do
  block {
    require 'fileutils'
    FileUtils.mv Dir.glob("#{current_data_directory}/*"), node.postgresql.server.data_directory, :verbose => true
    FileUtils.chown "postgres", "postgres", Dir.glob("#{node.postgresql.server.data_directory}/*")
  }
  only_if {moving_data_directory}
end

# For some reason, moving symbolic links with ruby screws up the access rights
# on the source files, even though they aren't moved.
file "/etc/ssl/private/ssl-cert-snakeoil.key" do
  owner "postgres"
  group "postgres"
  mode '0400'
end

file "/etc/ssl/certs/ssl-cert-snakeoil.pem" do
  owner "postgres"
  group "postgres"
  mode '0444'
end

  # just double check the conf file
  template "#{node[:postgresql][:dir]}/postgresql.conf" do
    source "debian.postgresql.conf.erb"
    owner "postgres"
    group "postgres"
    mode 0600
    notifies :restart, resources("service[postgresql]")
  end

#end
# empty ruby block resource hack to notify service resource based on another condition
# ensure postgres is running
ruby_block "start postgres service" do
  block {}
  notifies :start, resources("service[postgresql]"), :immediately
end
