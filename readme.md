Capify Cloud
====================================================

coshx/capify-cloud for automating autoscaled deployment on EC2


------------------------------
Cap <role> <environment> deploy

Deploys git to a prototype instance, creates a new ami based on the updated prototype instance and updates
 the autoscale configuration to use the updated ami in new scaling activity.  

-----------------------------


Prototype instance:
----
- Must have a single autoscaled role
- Can have an additional non-autoscaled role such as web
- Must have tags containing:
   ```
    Options => "prototype" 
    Project => project name which matches name in cloud.yml
    Roles => the autoscaled role like :app, optionally a secondary not-autoscaled role like :web 
   ```

Autoscaled role
----
- Must have one and only one prototype instance
- Must be declared using the cloud_roles tag within deploy.rb 
 	
    ```ruby
	cloud_roles :app #, :worker, :db, :solr, :cron  #do not use web role here.
	```
- Cannot be called :web 
- If the role is intended to use a loadbalancer, it should be flagged cloud.yml (see :load_balanced: app below)

Environment
---

- Must be declared using the cloud_stages tag within deploy.rb

	```ruby
	cloud_stages [:sandbox, :staging, :production]
	```
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


	





