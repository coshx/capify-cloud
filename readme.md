Capify Cloud
====================================================

coshx/capify-cloud for automating autoscaled deployment on EC2


------------------------------

To deploy run: <br>

cap <b><i> autoscaled-role environment </i></b> deploy

Deploys git to the autoscaled-role's prototype instance, creates a new ami of
the updated prototype instance, updates the autoscale configuration to use the
updated ami in new scaling activity for that role/environment.


-----------------------------

we'll be writing a file ~/.#{application}, so make sure to source this in your ~/.bashrc BEFORE any lines that return


additionally required at the top of application.rb

ENV['DB_HOST'] = File.read("../.unwaste").sub("export DB_HOST=","")


for example,


require File.expand_path('../boot', __FILE__)

require 'rails/all'
require 'sunspot_rails'
require 'delayed_job'
require 'will_paginate/array'
require 'dynamic_form'

ENV['DB_HOST'] = File.read("../.unwaste").sub("export DB_HOST=","")

if defined?(Bundler)
   Bundler.require(:default, :assets, Rails.env)
end

module Beam

  class Application < Rails::Application


-----------------------------


Prototype instance:
----
- Must have a single autoscaled role such as :app
- Must not have the same autoscaled role as another prototype instance.
- Can have an additional non-autoscaled role such as :web
- Must have tags containing:
   ```
    Options => "prototype"

    Project => project name which matches name in cloud.yml

    Roles => the autoscaled role like :app, optionally a secondary
             not-autoscaled role like :web
   ```

Autoscaled role
----
- Must have a single prototype instance
- Must be declared using the cloud_roles tag within deploy.rb

    ```ruby
	cloud_roles :app #, :worker, :db, :solr, :cron  #do not use web role here.
	```
- Cannot be called :web
- If the role is intended to use a loadbalancer, it should be flagged within
  cloud.yml (see :load_balanced: app below)


Not-Autoscaled roles
---
- Can be used on multiple primary instances
- Must NOT be declared using the cloud_roles tag within deploy.rb
- :web is a required not-autoscaled role because it's part of capistrano
  default tasks


Environments
---

- Must be declared using the cloud_stages tag within deploy.rb

	```ruby
	cloud_stages [:sandbox, :staging, :production]
	```
- A prototype instance for a given role must exist for each environment.  So if
  there are three environments and two roles, then there must be two prototype
  instances for each of the three environments which is a total of 6 prototype
  instances.

- Environment specifics must be defined within config/cloud.uml

	```
	:cloud_providers: ['AWS']
	:AWS:
	  :aws_access_key_id: 'KEY_ID'
	  :aws_secret_access_key: 'SECRET'
	  :sandbox:
	    :project_tag: "sandbox.network.unwasteny.org"
	    :params:
	      :region: 'us-east-1'
	      :availability_zone: 'us-east-1a'
	      :instance_type: 'm1.large'
	      :load_balanced: app
	  :staging:
	    :project_tag: "staging.network.unwasteny.org"
	    :params:
	      :region: 'us-east-1'
	      :availability_zone: 'us-east-1a'
	      :instance_type: 'm1.large'
	      :load_balanced: app
	  :production:
	    :project_tag: "production.network.unwasteny.org"
	    :params:
	      :region: 'us-east-1'
	      :availability_zone: 'us-east-1a'
	      :instance_type: 'm1.large'
	      :load_balanced: app
		```
