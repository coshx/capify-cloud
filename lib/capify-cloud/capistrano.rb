require File.join(File.dirname(__FILE__), '../capify-cloud')
require 'colored'

Capistrano::Configuration.instance(:must_exist).load do  

  def capify_cloud
    @capify_cloud ||= CapifyCloud.new(fetch(:cloud_config, 'config/cloud.yml'))
  end

  namespace :deploy do
    after "deploy", "autoscale:deploy"
  end

  namespace :autoscale do
    before "autoscale:create", "autoscale:chmod"
    after "autoscale:deploy", "autoscale:cleanup", "autoscale:info"
    after "autoscale:create", "autoscale:info"
    after "autoscale:delete", "autoscale:delete_groups", "autoscale:delete_configurations","autoscale:info"

    desc "Autoscales deployment of a unique role"
    task :deploy do
      capify_cloud.autoscale_deploy
    end

    desc "Deletes autoscale back to primary servers"
    task :delete do
      terminate_group_instances
    end
    task :terminate_group_instances do
      capify_cloud.delete_all_autoscale_group_instances
    end
    task :delete_groups do
      sleep(5)
      capify_cloud.delete_all_autoscale_groups
    end
    task :delete_configurations do
      capify_cloud.delete_all_autoscale_configuration
    end

    desc "Creates new autoscale configuration"
    task :create do
      capify_cloud.create_autoscale
    end

    desc "Creates a new launch configuration"
    task :update do
      capify_cloud.update_autoscale
    end

    desc "Prints information about load balancers"
    task :info do
      begin capify_cloud.autoscale_config_information ; rescue StandardError => e ;  puts e ; end
    end

    task :chmod, :except => { :no_release => true } do
      run "#{try_sudo} chmod 600 /home/bitnami/.ssh/id_rsa"
    end

    desc "Keeps limited number of prior launch configurations (in keeping with the number of ami)"
    task :cleanup do
      capify_cloud.describe_auto_scaling_groups.body['DescribeAutoScalingGroupsResult'].each do |auto_scaling_group|
        auto_scaling_group.each do |group|
          if(group.is_a?(Array))
            group.select {|f| f["AutoScalingGroupName"] }.each do |array|
              if array['Instances'].empty?
                groupname = array['AutoScalingGroupName']
                launchconfig = array['LaunchConfigurationName']
                capify_cloud.delete_auto_scaling_group(groupname)
              end
            end
          end
        end
      end
    end
  end
  namespace :ami do
    after "ami", "ami:cleanup"

    desc "Prints latest ami based on role"
    task :latest do
      ami_id = capify_cloud.find_latest_ami(autoscale_role)
      ami_tags = capify_cloud.image_tags(ami_id)
      puts ami_id+" "+ami_tags.to_s
    end

    task :create do
      capify_cloud.create_ami
    end

    desc "Keeps limited number of ami on AWS"
      task :cleanup do
       #
    end
  end

  namespace :cloud do

    desc "Prints out all cloud instances. index, name, instance_id, size, DNS/IP, region, tags"
    task :status do
      capify_cloud.display_instances
    end

    task :date do
      run "date"
    end

    desc "Prints list of cloud server names"
    task :server_names do
      puts capify_cloud.server_names.sort
    end
    
    desc "Allows ssh to instance by id. cap ssh <INSTANCE NAME>"
    task :ssh do
      server = variables[:logger].instance_variable_get("@options")[:actions][1]
      instance = numeric?(server) ? capify_cloud.desired_instances[server.to_i] : capify_cloud.get_instance_by_name(server)
      port = ssh_options[:port] || 22 
      command = "ssh -p #{port} #{user}@#{instance.contact_point}"
      puts "Running `#{command}`"
      exec(command)
    end
  end

  def cloud_stages(stages)
    ARGV.each do|argv|
      capify_cloud.define_stage(argv) if stages.to_s.include? argv.to_s
    end
    stages.each do |stage|
      task stage do ;
        capify_cloud.define_stage(stage) #in case want to change in the middle of deploy.rb method
      end
    end
  end

  def cloud_roles(*roles)
    ARGV.each do|argv|
      capify_cloud.define_role(argv) if roles.to_s.include? argv.to_s
    end
    roles.each {|role| cloud_role(role)}
  end

  def cloud_role(role_name_or_hash)
    role = role_name_or_hash.is_a?(Hash) ? role_name_or_hash : {:name => role_name_or_hash,:options => {}}
    @roles[role[:name]]
    instances = capify_cloud.get_instances_by_role(role[:name])
    task role[:name].to_sym do
      remove_default_roles
      instances.each do |instance|
        define_role(role, instance)
        instance_roles = instance.tags["Roles"].split(%r{,\s*})
        instance_roles.each do |role_tag|
          define_role({:name => role_tag}, instance)
        end
      end
    end
  end

  def define_role(role, instance)
    new_options = {}
    instance.tags["Options"].split(%r{,\s*}).each { |option| new_options[option.to_sym] = true} rescue false
    if new_options
      role role[:name].to_sym, instance.contact_point, new_options
    else
      role role[:name].to_sym, instance.contact_point
    end
  end

  def remove_default_roles	 	
    roles.reject! { true }
  end
  

end
