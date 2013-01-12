require File.join(File.dirname(__FILE__), '/capify-cloud')
require 'colored'

Capistrano::Configuration.instance(:must_exist).load do

  def capify ; @capify ||= CapifyCloud.new(fetch(:cloud_config, 'config/cloud.yml')) end

  namespace :deploy do
    before "deploy:web:disable", "web"
    before "deploy:web:enable", "web"

    after "deploy", #capistrano deploy
          "deploy:autoscale"

    task :autoscale do
      #update_env_var(capify.params)
      #migrate_database(capify.database)
      image = capify.create_image(capify.prototype) ; return if image.nil?
      capify.update_autoscale(image)
      capify.update_loadbalancer(image)
      capify.cleanup
    end

  end

  namespace :autoscale do

    namespace :try do
      task :set10 do
        capify.set10
      end
      task :set1 do
        capify.set1
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

  def migrate_database(db_host)
    run "cd ~/apps/unwaste_network/current && DB_HOST=#{db_host} RAILS_ENV=production rake db:migrate"
  end
  def update_env_var(params)
    env_var_content = ''
    params.each do |key, value|
      env_var_content << "ENV['#{key.to_s.upcase}']=\"#{value}\"\n"
    end
    write("#{fetch(:deploy_to)}shared/environment.rb",env_var_content)
  end
  def write(filename,content)
    run "#{try_sudo} touch #{filename}"
    run "#{try_sudo} chmod a+w #{filename}"
    put content, filename
  end
  def cloud_stages(stages)
    ARGV.each do|stage|
      if stages.to_s.include? stage
        capify.stage = stage
        set :stage, stage
        task stage do end #cap will still run 'stage' task, although not needed
      end
    end
  end
  def cloud_roles(*roles)
    reject_default_roles
    ARGV.each do|role|
      if roles.to_s.include? role
        task role.to_sym do
          capify.role = role
          instance = capify.prototype
          role 'web'.to_sym, instance.public_ip_address
          role role.to_sym, instance.public_ip_address
        end
      end
    end
    task :web do
      capify.web_instances.each do |instance|
        role :web, instance.public_ip_address
      end
    end
  end
  def reject_default_roles
    roles.reject! { true }
  end

end
