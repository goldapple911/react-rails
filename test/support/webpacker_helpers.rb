module WebpackerHelpers
  PACKS_DIRECTORY =  File.expand_path("../../dummy/public/packs", __FILE__)

  module_function
  def available?
    defined?(Webpacker)
  end

  def when_webpacker_available
    if available?
      yield
    end
  end

  def compile
    return if !available?
    clear_webpacker_packs
    Dir.chdir("./test/dummy") do
      capture_io do
        Rake::Task['webpacker:compile'].reenable
        Rake::Task['webpacker:compile'].invoke
      end
    end
    # Reload cached JSON manifest:
    Webpacker::Manifest.load
  end

  def compile_if_missing
    if !File.exist?(PACKS_DIRECTORY)
      compile
    end
  end

  def clear_webpacker_packs
    FileUtils.rm_rf(PACKS_DIRECTORY)
  end

  # Start a webpack-dev-server
  # Call the block
  # Make sure to clean up the server
  def with_dev_server
    # Start the server in a forked process:
    webpack_dev_server = Dir.chdir("test/dummy") do
      spawn "RAILS_ENV=development ./bin/webpack-dev-server "
    end

    detected_dev_server = false

    # Wait for it to start up, make sure it's there by connecting to it:
    30.times do |i|
      begin
        # Make sure that the manifest has been updated:
        Webpacker::Manifest.load("./test/dummy/public/packs/manifest.json")
        webpack_manifest = Webpacker::Manifest.instance.data
        example_asset_path = webpack_manifest.values.first
        if example_asset_path.nil?
          # Debug helper
          # puts "Manifest is blank, all manifests:"
          # Dir.glob("./test/dummy/public/packs/*.json").each do |f|
          #   puts f
          #   puts File.read(f)
          # end
          next
        end
        # Make sure the dev server is up:
        open("http://localhost:8080/application.js")
        if !example_asset_path.start_with?("http://localhost:8080")
          raise "Manifest doesn't include absolute path to dev server"
        end

        detected_dev_server = true
        break
      rescue StandardError => err
        puts err.message
      ensure
        sleep 0.5
        # debug counter
        # puts i
      end
    end

    # If we didn't hook up with a dev server after waiting, fail loudly.
    if !detected_dev_server
      raise "Failed to start dev server"
    end

    # Call the test block:
    yield
  ensure
    # Kill the server process
    puts "Killing webpack dev server"
    puts Process.kill("HUP", webpack_dev_server)
    Process.wait(webpack_dev_server)
    puts $?
    check_cmd = "lsof -i :8080 -S"
    puts check_cmd
    puts `#{check_cmd}`
    puts `kill -9 #{webpack_dev_server}`
    # Remove the dev-server packs:
    WebpackerHelpers.clear_webpacker_packs
    puts "Killed."
  end
end
