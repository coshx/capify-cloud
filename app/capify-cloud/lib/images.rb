class Images

  def initialize(connection)
    @connection = connection
  end

  def create(prototype_instance)
    image_name = image_desc = "#{Time.now.utc.iso8601.gsub(':','.')}"
    create_image_response = @connection.create_image(prototype_instance.id,image_name, image_desc)
    image = @connection.images.get(create_image_response.body['imageId'])
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
      @connection.create_tags(image.id, {"Name"=>'name',"Stage" => prototype_instance.tags["Stage"], "Roles" => prototype_instance.tags['Roles'], "Version" => Time.now.utc.iso8601.gsub(':','.'), "Options" => "no_release"})
      puts "\nami ok: "+image.id unless Fog.mocking?
    end
    return image
  end
end



