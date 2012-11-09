require File.join(File.dirname(__FILE__), '/capify-cloud')
require 'colored'

Capistrano::Configuration.instance(:must_exist).load do

  namespace :deploy do
    before "deploy:web:disable", "web"
    before "deploy:web:enable", "web"

    after "deploy", #capistrano deploy
          "deploy:autoscale"

    task :autoscale do
      current_servers = find_servers_for_task(current_task)
      prototype_ip = current_servers.first
      #migrate_database()
      #update_env_var()
      image = capify.create_image(capify.find_instance_by_ip(prototype_ip))
      unless image.nil?
        capify.update_autoscale(image)
        capify.update_loadbalancer
        capify.cleanup()
      end
    end

  end

  namespace :autoscale do

    namespace :clean do
      task :default do
        capify.cleanup()
      end
    end

    namespace :info do
      task :default do
        capify.print_autoscale()
      end
      task :config do
        capify.print_configuration()
      end
      task :configuration do
        capify.print_configuration()
      end
      task :ami do
        capify.print_images()
      end
      task :groups do
        capify.print_groups()
      end
      task :snapshot do
        capify.print_snapshots()
      end
      task :prototype do
        capify.print_prototypes()
      end
    end

  end

 def capify ; @lib ||= CapifyCloud.new(fetch(:cloud_config, 'config/cloud.yml')) end

  def migrate_database
    db_host = capify.config_params[:DB_HOST]
    run "cd ~/apps/unwaste_network/current && DB_HOST=#{db_host} RAILS_ENV=production rake db:migrate"
  end
  def update_env_var
    env_var_content = ''
    capify.config_params.each do |key, value|
      env_var_content << "ENV['#{key.to_s.upcase}']=\"#{value}\"\n"
    end
    write("#{fetch(:deploy_to)}shared/environment.rb",env_var_content)
  end
  def write(filename,content)
    run "#{try_sudo} touch #{filename}"
    run "#{try_sudo} chmod a+w #{filename}"
  end
  def cloud_stages(stages)
    ARGV.each do|stage|
      if stages.to_s.include? stage
        capify.stage = stage
        set :stage, stage
        task stage do end
      end
    end
  end
  def cloud_roles(*roles)
    reject_default_roles
    task :web do
      capify.get_instances_by_role(:web).each do |instance|
        role :web, instance.public_ip_address
      end
    end
    ARGV.each do|role|
      if roles.to_s.include? role
        task role.to_sym do
          capify.role = role
          instance = capify.find_prototype_by_role(role)
          role role.to_sym, instance.public_ip_address
        end
      end
    end
  end
  def reject_default_roles
    roles.reject! { true }
  end

end
