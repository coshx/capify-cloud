require 'spec_helper'

describe "Capify" do

  before (:all) do
    Fog.mock!
    capify.stage = 'sandbox'
    capify.role = 'app'
   end

  describe "autoscale" do

    describe "create" do

      before(:all) do
        @prototype_image = capify.create_image(mock_new_prototype_instance)
        @create_autoscale_return = capify.create_autoscale(@prototype_image)
      end

      it "returns a hash containing newly created autoscaling group and launch configuration" do
        @create_autoscale_return.has_key?(:group).should be_true
        @create_autoscale_return.has_key?(:configuration).should be_true
      end

      it "creates launch configuration with prototype image id" do
        @create_autoscale_return[:configuration].image_id.should eql(@prototype_image.id)
      end

      it "creates autoscaling group that propagates tags at launch" do
        @create_autoscale_return[:group].tags.each do |hash|
          hash.has_key?('propagate_at_launch').should be_true
          hash['propagate_at_launch'].should eql('true')
        end
      end

      it "creates autoscaling group where Options=>no_release" do
        options = convert_tag_array_to_hash(@create_autoscale_return[:group])['Options']
        options.should eql('no_release')
      end

      it "assignes role and stage of autoscaling group to be the same as the prototype image specified within launch configuration image_id" do
        tags = convert_tag_array_to_hash(@create_autoscale_return[:group])
        tags['Roles'].should eql(@prototype_image.tags['Roles'])
        tags['Stage'].should eql(@prototype_image.tags['Stage'])
      end
    end

    describe "update" do

      before(:all) do
        @prototype_image = capify.create_image(mock_new_prototype_instance)
        @create_autoscale_return = capify.create_autoscale(@prototype_image)
        @updated_prototype_image = capify.create_image(mock_new_prototype_instance)
        @update_autoscale_return = capify.update_autoscale(@updated_prototype_image)
      end

      it "returns a hash containing newly created autoscaling group and launch configuration" do
        @update_autoscale_return.has_key?(:group).should be_true
        @update_autoscale_return.has_key?(:configuration).should be_true
      end

      it "updates launch configuration with updated image id" do
        @update_autoscale_return[:configuration].image_id.should eql(@updated_prototype_image.id)
      end

    end

    describe "cleanup" do

       before(:each) do
         capify.create_autoscale(capify.create_image(mock_new_prototype_instance))
         capify.update_autoscale(capify.create_image(mock_new_prototype_instance))
         capify.update_autoscale(capify.create_image(mock_new_prototype_instance))
         capify.cleanup()
       end

       let(:remaining_launch_configurations){autoscale_connection.describe_launch_configurations.body['DescribeLaunchConfigurationsResult']['LaunchConfigurations']}
       let(:active_launch_configuration){autoscale_connection.describe_auto_scaling_groups.body['DescribeAutoScalingGroupsResult'].first.select {|a| a.is_a? Array}.first}

       let(:active_images){}
       let(:remaining_images){}


       it "deletes inactive/out-of-date autoscale configuration files" do
         remaining_launch_configurations.count eql(1)
       end

       it "does not delete active/in-use autoscale configuration files" do
         remaining_launch_configuration_name = remaining_launch_configurations.first['LaunchConfigurationName']
         active_launch_configuration_name = active_launch_configuration.first["LaunchConfigurationName"]
         remaining_launch_configuration_name.should eql(active_launch_configuration_name)
       end

       it "deletes inactive/out-of-date images" do
         pending
       end

       it "does not delete active/in-use images" do
         pending
       end

       it "deletes inactive/out-of-date snapshots" do
         pending "Fog persistence of a mock snapshot upon mock image creation"
       end

       it "does not delete active/in-use snapshots" do
         pending "Fog persistence of a mock snapshot upon mock image creation"
       end

    end
  end
end
