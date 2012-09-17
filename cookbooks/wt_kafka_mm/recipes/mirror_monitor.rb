#
# Author: Jeff Berger (<jeff.berger@webtrends.com>)
# Cookbook Name:: wt_kafka_mm
# Recipe:: mirror_monitor
#
# Copyright 2012, Webtrends
#

log "Deploy build is #{ENV["deploy_build"]}"
if ENV["deploy_build"] == "true" then
    log "The deploy_build value is true so un-deploy first"
else
    log "The deploy_build value is not set or is false so we will only update the configuration"
end

log_dir = File.join(node['wt_common']['log_dir_linux'], "/mirrormonitor")
install_dir = File.join(node['wt_common']['install_dir_linux'], "/mirrormonitor")

user = node['wt_kafka_mm']['user']
group = node['wt_kafka_mm']['group']

java_home = node['java']['java_home']
java_opts = node['wt_kafka_mm']['java_opts']

jmx_port = node['wt_kafka_mm']['monitor_jmx_port']

###############################################################
#
# Helper Functions
#
###############################################################

#Get the zookeeper instances in the specified environment
def getZookeeperPairs(node, env)

	# get the correct environment for the zookeeper nodes
	zookeeper_port = node['zookeeper']['client_port']

	# grab the zookeeper nodes that are currently available
	zookeeper_pairs = Array.new
	if not Chef::Config.solo
		search(:node, "role:zookeeper AND chef_environment:#{env}").each do |n|
			zookeeper_pairs << n[:fqdn]
		end
	end

	log "#{zookeeper_pairs.size} instances of zookeeper found found in #{env}"

	# fall back to attribs if search doesn't come up with any zookeeper roles
	# if zookeeper_pairs.count == 0
	#	node[:zookeeper][:quorum].each do |i|
	#		zookeeper_pairs << i
	#	end
	# end

	# append the zookeeper client port (defaults to 2181)

	i = 0
	while i < zookeeper_pairs.size do
		zookeeper_pairs[i] = zookeeper_pairs[i].concat(":#{zookeeper_port}")
		i += 1
	end

	return zookeeper_pairs
end

#update the config files
def processConfTemplates (install_dir, node, log_dir)
 
	#Ugly - manually create the json string
	srcEnvs = "{\"environments\":["
	count = 0;
	node['wt_kafka_mm']['sources'].each { |src_env|  
	  if count !=  0
	    srcEnvs += ","
	  end             	                                    
	  srcEnvs += "{\"name\":\"#{src_env}\",\"zkconnect\":\"#{getZookeeperPairs(node, src_env)}\"}" 
	  count += 1
	}
	srcEnvs += "]}"
	                                    
	#zookeeper_pairs_target = getZookeeperPairs(node, node["wt_kafka_mm"]["target"])
	tgtEnv = "{\"environments\":[{\"name\":\"#{node["wt_kafka_mm"]["target"]}\",\"zkconnect\":\"#{getZookeeperPairs(node, node["wt_kafka_mm"]["target"])}\"}]}"	

	# Set up the main mirror monitor config
    	template "#{install_dir}/conf/mirrormonitor.properties" do
	  source  "monitor.mirrormonitor.properties.erb"
	  owner   "root"
	  group   "root"
	  mode    00644
	  variables({
	    :mirrorsources  => srcEnvs,
	    :mirrormachineid => node["wt_kafka_mm"]["id"],
	    :mirrortarget => tgtEnv,
	    :averagecount => node["wt_kafka_mm"]["averagecount"],
	    :ratethreshold => node["wt_kafka_mm"]["ratethreshold"],
	    :avgthreshold => node["wt_kafka_mm"]["avgthreshold"],
	    :producerate => node["wt_kafka_mm"]["producerate"]
	  })
	end
	
	# Set up the monitor producer config
    	template "#{install_dir}/conf/producer.properties" do
	  source  "monitor.producer.properties.erb"
	  owner   "root"
	  group   "root"
	  mode    00644
	  variables({
	  })
	end
	
	# Set up the monitor consumer config
    	template "#{install_dir}/conf/consumer.properties" do
	  source  "monitor.consumer.properties.erb"
	  owner   "root"
	  group   "root"
	  mode    00644
	  variables({
	  })
	end
	
	# log4j
	template "#{install_dir}/conf/log4j.properties" do
	  source  "log4j.properties.erb"
	  owner   "root"
	  group   "root"
	  mode    00644
	  variables({
	    :log_file => "#{log_dir}/mirrormonitor.log",
	    :log_level => node['wt_kafka_mm']['log_level']
	  })
	end
end

###############################################################
#
# Begin deploy
#
###############################################################

if ENV["deploy_build"] == "true" then

	# create the log directory
	directory log_dir do
		owner   user
		group   group
		mode    00755
		recursive true
		action :create
	end

	# create the install bin directory
	directory "#{install_dir}/bin" do
		owner "root"
		group "root"
		mode 00755
		recursive true
		action :create
	end
	
	# create the install conf directory
	directory "#{install_dir}/conf" do
		owner "root"
		group "root"
		mode 00755
		recursive true
		action :create
	end

	# create the lib directory
	directory "#{install_dir}/lib" do
		owner "root"
		group "root"
		mode 00755
		recursive true
		action :create
	end

	#pull down the mirror maker dependencies and copy to /lib
	#getLib("#{install_dir}/lib")

	# Set up the control script
	template "#{install_dir}/bin/service-control" do
		source  "monitor.service-control.erb"
		owner "root"
		group "root"
		mode  00755
		variables({
			:log_dir => log_dir,
			:install_dir => install_dir,
			:java_home => java_home,
			:java_class => "com.webtrends.mirrormonitor.MirrorMonitorDaemon",
			:java_port => jmx_port,
			:java_opts => java_opts
		})
	end

#	runit_service "mirrormonitor" do
#	  template_name "mirrormonitor"	#/templates/sv-mirrormonitor-run.erb
#	    options({
#	      :install_dir => install_dir,
#	      :user => user,
#	      :jmx_port => jmx_port
#	    })
#	  end
end

#Do this in all situations
processConfTemplates(install_dir, node, log_dir)
