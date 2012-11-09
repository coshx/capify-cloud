class Images

  def initialize(compute_connection, role, stage)
    @compute_connection = compute_connection
    @stage = stage
    @role = role
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

  def print_images
    ami = all_images
    puts 'all available images'
    ami.each do |image|
      snapshot_id = snapshot_id_of_ami(image.id)
      snapshot =  @compute_connection.snapshots.get(snapshot_id)
      puts "  #{image.id} -> #{snapshot_id} #{if snapshot.nil?;'(does not exist)'else; '(available)'end}  #{image.tags['Name']}"
    end
  end

  def print_snapshots
    active = active_snapshots()
    inactive = inactive_snapshots()
    puts "  active snapshots"
    active.each do |snap_id|
      puts "    #{snap_id} "
    end
    if inactive.count>0
      puts "  snapshots for images which no longer exist"
      inactive.each do |unused_snap_id|
        puts "    #{unused_snap_id}"
      end
    end
  end

  private

  def cleanup_snapshots
    inactive_snapshots.each do |snap_id|
      puts "deleting snapshot #{snap_id}"
      @compute_connection.delete_snapshot(snap_id)
    end
  end

  def all_images
    @compute_connection.images.select {|image| !image.is_public}
  end

  def all_snapshots
    @compute_connection.snapshots.all
  end

  def snapshot_id_of_ami(image_id)
    ami = @compute_connection.images.get(image_id)
    if ami.nil?
      return '- snapshot unavailable -'
    else
      return ami.block_device_mapping.first['snapshotId']
    end
  end

  def active_snapshots
    active = []
    all_images.each do |image|
      snapshot_id = snapshot_id_of_ami(image.id)
      active.push(snapshot_id)
    end
    return active
  end

  def inactive_snapshots
   active = active_snapshots()
   inactive = []
   all_snapshots.each do |snapshot|
      if !active.include?(snapshot.id) && snapshot.description.include?("Created by CreateImage")
        inactive.push(snap.id)
      end
    end
   return inactive
  end

end



