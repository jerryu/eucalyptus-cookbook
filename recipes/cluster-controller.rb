#
# Cookbook Name:: eucalyptus
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
include_recipe "eucalyptus::default"
## Install binaries for the CC
if node["eucalyptus"]["install-type"] == "packages"
  yum_package "eucalyptus-cc" do
    action :install
    options node['eucalyptus']['yum-options']
  end
else
  ## Install CC from source from internal repo if it exists
  execute "export JAVA_HOME='/usr/lib/jvm/java-1.7.0-openjdk.x86_64' && export JAVA='$JAVA_HOME/jre/bin/java' && export EUCALYPTUS='#{node["eucalyptus"]["home-directory"]}' && make && make install" do
    cwd "#{node["eucalyptus"]["source-directory"]}/eucalyptus/"
    only_if "ls #{node["eucalyptus"]["source-directory"]}/eucalyptus/cluster"
    creates "#{node["eucalyptus"]["source-directory"]}/eucalyptus/cluster/generated"
  end
  ## Install CLC from open source repo if it exists
  execute "export JAVA_HOME='/usr/lib/jvm/java-1.7.0-openjdk.x86_64' && export JAVA='$JAVA_HOME/jre/bin/java' && export EUCALYPTUS='#{node["eucalyptus"]["home-directory"]}' && make && make install" do
    cwd "#{node["eucalyptus"]["source-directory"]}/"
    only_if "ls #{node["eucalyptus"]["source-directory"]}/cluster"
    creates "#{node["eucalyptus"]["source-directory"]}/cluster/generated"
  end
  ### Create symlink for eucalyptus-cloud service
  tools_dir = "#{node["eucalyptus"]["source-directory"]}/tools"
  if node['eucalyptus']['source-repo'].end_with?("internal")
    tools_dir = "#{node["eucalyptus"]["source-directory"]}/eucalyptus/tools"
  end

  execute "ln -s #{tools_dir}/eucalyptus-cc /etc/init.d/eucalyptus-cc" do
    creates "/etc/init.d/eucalyptus-cc"
  end

  execute "chmod +x #{tools_dir}/eucalyptus-cc"
end

template "#{node["eucalyptus"]["home-directory"]}/etc/eucalyptus/eucalyptus.conf" do
  source "eucalyptus.conf.erb"
  action :create
end

execute "export EUCALYPTUS='#{node["eucalyptus"]["home-directory"]}' && #{node["eucalyptus"]["home-directory"]}/usr/sbin/euca_conf --setup"

ruby_block "Get cluster keys from CLC" do
  block do
    node.set["eucalyptus"]["topology"]["clusters"][node["eucalyptus"]["local-cluster-name"]]["cc-1"] = node["ipaddress"]
    if node["eucalyptus"]["topology"]["clc-1"] != ""
      ### CLC is seperate
      clc_ip = node["eucalyptus"]["topology"]["clc-1"]
      clc  = search(:node, "ipaddress:#{clc_ip}").first
      node.set["eucalyptus"]["cloud-keys"][node["eucalyptus"]["local-cluster-name"]] = clc["eucalyptus"]["cloud-keys"][node["eucalyptus"]["local-cluster-name"]]
    else
      node.set["eucalyptus"]["cloud-keys"][node["eucalyptus"]["local-cluster-name"]] = node["eucalyptus"]["cloud-keys"][node["eucalyptus"]["local-cluster-name"]]
    end
    node.save
    node["eucalyptus"]["cloud-keys"][node["eucalyptus"]["local-cluster-name"]].each do |key_name,data|
     file_name = "#{node["eucalyptus"]["home-directory"]}/var/lib/eucalyptus/keys/#{key_name}"
     File.open(file_name, 'w') do |file|  
       file.puts Base64.decode64(data)
     end
     require 'fileutils'
     FileUtils.chmod 0700, file_name
     FileUtils.chown 'eucalyptus', 'eucalyptus', file_name
    end
  end
  not_if "#{Chef::Config[:solo]}"
end

service "eucalyptus-cc" do
  action [ :enable, :start ]
  supports :status => true, :start => true, :stop => true, :restart => true
end
