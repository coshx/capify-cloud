Capify Cloud
====================================================

coshx/capify-cloud for automating autoscaled deployment on EC2


------------------------------
Cap <role> <environment> deploy

Deploys git to a prototype instance, then creates a new ami based on the updated prototype instance and updates
 the autoscale configuration to use the updated ami.
-----------------------------


In your deploy.rb:

```ruby
require "capify-cloud/capistrano"

cloud_stages [:production]

cloud_roles :app, :role2

```

cloud_roles clarified logic. note that within each role task as declared by cloud_roles, there are capistrano roles
   being declared to match all the roles contained within any prototype instance


```ruby
def cloud_role(role_name)
    instances = capify_cloud.get_instances_by_role(role[:name])
    task role_name do
      instances.each do |instance|
        define_role(role, instance)
        instance_roles = instance.tags["Roles"].split(%r{,\s*})
        instance_roles.each do |role_tag|
          define_role({:name => role_tag}, instance)
        end
      end
    end
  end
```



Will generate

```ruby

task :app do
  role :web, {public dns fetched from Amazon}, :cron=>true, :resque=>true
end

task :production do

end


```

Additionally

```ruby
require "capify-cloud/capistrano"
cloud_roles :db
```

Will generate

```ruby
task :server-2 do
  role :db, {server-2 public or private IP, fetched from Brightbox}
end

task :server-3 do
  role :db, {server-3 public dns fetched from Amazon}
end

task :db do
  role :db, {server-2 public or private IP, fetched from Brightbox}
  role :db, {server-3 public dns fetched from Amazon}
end
```

Running

```ruby
cap web cloud:date
```

will run the date command on all server's tagged with the web role

Running

```ruby
cap server-1 cloud:register_instance -s loadbalancer=elb-1
```

will register server-1 to be used by elb-1

Running

```ruby
cap server-1 cloud:deregister_instance
```

will remove server-1 from whatever instance it is currently
registered against.

Running

```ruby
cap cloud:status
```

will list the currently running servers and their associated details
(public dns, instance id, roles etc)

Running

```ruby
cap cloud:ssh #
```

will launch ssh using the user and port specified in your configuration.
The # argument is the index of the server to ssh into. Use the 'cloud:status'
command to see the list of servers with their indices.

More options
====================================================

In addition to specifying options (e.g. 'cron') at the server level, it is also possible to specify it at the project level.
Use with caution! This does not work with autoscaling.

```ruby
cloud_roles {:name=>"web", :options=>{:cron=>"server-1"}}
```

Will generate

```ruby
task :server-1 do
  role :web, {server-1 public dns fetched from Amazon}, :cron=>true
end

task :server-3 do
  role :web, {server-1 public dns fetched from Amazon}
end

task :web do
  role :web, {server-1 public dns fetched from Amazon}, :cron=>true
  role :web, {server-3 public dns fetched from Amazon}
end
```

Which is cool if you want a task like this in deploy.rb

```ruby
task :update_cron => :web, :only=>{:cron} do
  Do something to a server with cron on it
end

cloud_roles :name=>:web, :options=>{ :default => true }
```

Will make :web the default role so you can just type 'cap deploy'.
Multiple roles can be defaults so:

```ruby
cloud_roles :name=>:web, :options=>{ :default => true }
cloud_roles :name=>:app, :options=>{ :default => true }
```

would be the equivalent of 'cap app web deploy'

Cloud config
====================================================

This gem requires 'config/cloud.yml' in your project.
The yml file needs to look something like this:
  
```ruby
:cloud_providers: ['AWS', 'Brightbox']

:AWS:
  :aws_access_key_id: "YOUR ACCESS KEY"
  :aws_secret_access_key: "YOUR SECRET"
  :params:
    :region: 'eu-west-1'
  :load_balanced: true
  :project_tag: "YOUR APP NAME"
  
:Brightbox:
  :brightbox_client_id: "YOUR CLIENT ID"
  :brightbox_secret: "YOUR SECRET"
```
aws_access_key_id, aws_secret_access_key, and region are required for AWS. Other settings are optional.
brightbox_client_id and brightbox_secret: are required for Brightbox.
If you do not specify a cloud_provider, AWS is assumed.

If :load_balanced is set to true, the gem uses pre and post-deploy
hooks to deregister the instance, reregister it, and validate its
health.
:load_balanced only works for individual instances, not for roles.

The :project_tag parameter is optional. It will limit any commands to
running against those instances with a "Project" tag set to the value
"YOUR APP NAME".

## Development

Source hosted at [GitHub](http://github.com/ncantor/capify-cloud).
Report Issues/Feature requests on [GitHub Issues](http://github.com/ncantor/capify-cloud/issues).

### Note on Patches/Pull Requests

 * Fork the project.
 * Make your feature addition or bug fix.
 * Add tests for it. This is important so I don't break it in a
   future version unintentionally.
 * Commit, do not mess with rakefile, version, or history.
   (if you want to have your own version, that is fine but bump version in a commit by itself I can ignore when I pull)
 * Send me a pull request. Bonus points for topic branches.

## Copyright

Original version: Copyright (c) 2012 Forward. See [LICENSE](https://github.com/ncantor/capify-cloud/blob/master/LICENSE) for details.
