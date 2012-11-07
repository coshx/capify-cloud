class Images

  def initialize(compute_connection)
    @compute_connection = compute_connection
  end

  def create(prototype_instance)
    image_name = image_desc = "#{Time.now.utc.iso8601.gsub(':','.')}"
    create_image_response = @compute_connection.create_image(prototype_instance.id,image_name, image_desc)
    image = @compute_connection.images.get(create_image_response.body['imageId'])
    progress_output = ''
    Fog.wait_for do
      STDOUT.write "\r#{progress_output}"
      progress_output = progress_output+"."
      if progress_output.length>10 ; progress_output = '' end
      image.state != 'pending' || Fog.mocking?
    end
    if image.state == 'failed' && !Fog.mocking?
      puts "image creation failed, please try again in a few minutes."
    else
      @compute_connection.create_tags(image.id, {"Name"=>'name',"Stage" => prototype_instance.tags["Stage"], "Roles" => prototype_instance.tags['Roles'], "Version" => Time.now.utc.iso8601.gsub(':','.'), "Options" => "no_release"})
      puts "\nami ok: "+image.id unless Fog.mocking?
    end
    return image
  end

  def clean_up
    puts (images_sorted - images_sorted.take(2)).inspect
  end

  def images
    @compute_connection.images.select {|image| image.stage == get_stage && image.roles.include?(current_deploy_role.to_s)}
  end

  def sorted_images
    images.sort{|image1,image2|Time.parse(image2.version.sub(".",":")).to_i <=> Time.parse(image1.version.sub(".",":")).to_i}
  end

  def latest_image
    images_sorted[0].id
  end

  def remove_outdated_ami
    outdated_images = images_sorted - images_sorted.take(2)
    outdated_images.each do |image|
      compute.deregister_image(image.id)
    end
  end
end



