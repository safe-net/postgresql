# re-eval the data_directory attribute, based on this article:
# http://community.opscode.com/questions/77
node.default['postgresql']['server']['data_directory'] = "#{node['postgresql']['server']['data_directory_base']}/#{node[:postgresql][:version]}/main"