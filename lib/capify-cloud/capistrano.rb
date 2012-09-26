require File.join(File.dirname(__FILE__), '../capify-cloud')
require 'colored'

Capistrano::Configuration.instance(:must_exist).load do

  def capify_cloud
    @capify_cloud ||= CapifyCloud.new(fetch(:cloud_config, 'config/cloud.yml'))
  end

  def write(filename,content)
    run "#{try_sudo} touch #{filename}"
    run "#{try_sudo} chmod a+w #{filename}"
    put content, filename
  end

  namespace :deploy do
    before "deploy", "deploy:update_environmental_variables"
    after "deploy", "db:migrate", "autoscale:deploy", "autoscale:cleanup", "autoscale:replace_outdated_instances"
    before "deploy:web:disable", "web"
    before "deploy:web:enable", "web"

    task :update_environmental_variables, :except => { :no_release => true } do
      directory = fetch(:deploy_to)
      env_var_filename = "#{directory}shared/environment.rb"
      env_var_content = ''
      capify_cloud.config_params.each do |key, value|
        env_var_content << "ENV['#{key.to_s.upcase}']=\"#{value}\"\n"
      end
      write(env_var_filename,env_var_content)
    end
  end

  namespace :db do
    task :migrate, :except => { :no_release => true } do
      db_host = capify_cloud.config_params[:DB_HOST]
      run "cd ~/apps/unwaste_network/current && DB_HOST=#{db_host} RAILS_ENV=production rake db:migrate"
    end
  end

  namespace :autoscale do
    before "autoscale:create", "autoscale:chmod"
    after "autoscale:delete", "autoscale:delete_groups", "autoscale:delete_configurations"

    desc "Replaces autoscale instances with new instances launched form the latest ami"
    task :replace_outdated_instances do
      capify_cloud.replace_outdated_autoscale_instances
    end

    task :up do
      capify_cloud.scale_up
    end

    task :down do
      capify_cloud.scale_down
    end

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
      begin
        capify_cloud.delete_all_autoscale_groups
      rescue StandardError => e ;
        capify_cloud.delete_all_autoscale_groups
      end
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
      capify_cloud.remove_outdated_ami
      capify_cloud.describe_auto_scaling_groups.body['DescribeAutoScalingGroupsResult'].each do |auto_scaling_group|
        auto_scaling_group.each do |group|
          if(group.is_a?(Array))
            group.select {|f| f["AutoScalingGroupName"] }.each do |array|
              if array['Instances'].empty?
                groupname = array['AutoScalingGroupName']
                launchconfig = array['LaunchConfigurationName']
                puts "deleting autoscale configuration "+groupname
                capify_cloud.delete_auto_scaling_group(groupname)
                capify_cloud.delete_launch_configuration(launchconfig)
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
      ami_id = capify_cloud.find_latest_ami
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
      if stages.to_s.include? argv
        capify_cloud.define_stage(argv)
        task argv do
          capify_cloud.define_stage(argv)
          set :stage, argv
        end
      end
    end
  end

  def cloud_roles(*roles)
    task :web do
      capify_cloud.get_instances_by_role(:web).each do |instance|
        role :web, instance.contact_point
      end
    end
    ARGV.each do|argv|
      if roles.to_s.include? role = argv
        capify_cloud.define_role(role)
        capistrano_roles(role)
      end
    end
  end

  def capistrano_roles(role_name_or_hash)
    role = role_name_or_hash.is_a?(Hash) ? role_name_or_hash : {:name => role_name_or_hash,:options => {}}
    @roles[role[:name]]
    instances = capify_cloud.get_prototype_by_role(role[:name])
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
