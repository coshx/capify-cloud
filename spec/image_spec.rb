require 'spec_helper'

describe "Capify" do

  before (:all) do
    Fog.mock!
    capify.stage = 'sandbox'
    capify.role = 'app'
    @prototype_instance = mock_new_prototype_instance
    @prototype_image = capify.create_image(@prototype_instance)
  end

  describe "create_image"  do

    it "returns a fog image" do
       @prototype_image.should be_an_instance_of(Fog::Compute::AWS::Image)
    end

    it "creates image with the same role and stage as it's prototype instance" do
      @prototype_image.tags['Roles'].should eql(@prototype_instance.tags['Roles'])
      @prototype_image.tags['Stage'].should eql(@prototype_instance.tags['Stage'])
    end

  end

end