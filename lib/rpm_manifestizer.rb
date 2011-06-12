class RpmManifestizer

  attr_accessor :dry_run

  def initialize settings
    @settings = settings
  
    @cut_off_exceptions = [ "qt4-x11" ]
    @source_rpms = Hash.new
  end

  def create_manifest name, rpm_name
    filename =  "#{@settings.manifest_dir}/#{name}.manifest" 
    File.open( filename, "w") do |f2|
      source_rpm = `rpm -q --queryformat '%{SOURCERPM}' #{rpm_name}`
      @source_rpms[source_rpm] = Array.new

      raw = `rpm -q --queryformat '%{DESCRIPTION}' #{rpm_name}`
      parse_authors = false
      description = ""
      authors = Array.new
      raw.each_line do |line3|
        if line3 =~ /^Authors:/
          parse_authors = true
          next
        end
        if parse_authors
          if line3 =~ /^---/
            next
          end
          authors.push "\"#{line3.strip}\""
        else
          description += line3.chomp + "\\n"
        end
      end
      description.gsub! /"/, "\\\""
      description.strip!

      qf = '  "version": "%{VERSION}",\n'
      qf += '  "summary": "%{SUMMARY}",\n'
      qf += '  "homepage": "%{URL}",\n'
      qf += '  "license": "%{LICENSE}",\n'
      header = `rpm -q --queryformat '#{qf}' #{rpm_name}`

      f2.puts '{';
      f2.puts '  "schema_version": 1,'
      f2.puts "  \"name\": \"#{name}\","
      f2.puts header
      f2.puts "  \"description\": \"#{description}\","
      f2.puts '  "authors": [' + authors.join(",") + '],'
      f2.puts '  "maturity": "stable",'
      f2.puts '  "packages": {'
      f2.puts '    "openSUSE": {'
      f2.puts '      "11.4": {'
      f2.puts "        \"package_name\": \"#{rpm_name}\","
      f2.puts '        "repository": {'
      f2.puts '          "url": "http://download.opensuse.org/distribution/11.4/repo/oss/",'
      f2.puts '          "name": "openSUSE-11.4-Oss"'
      f2.puts '        },'
      f2.puts "        \"source_rpm\": \"#{source_rpm}\""
      f2.puts '      }'
      f2.puts '    }'
      f2.puts '  }'
      f2.puts '}'
    end
  end

  def requires_qt? rpm_name
    IO.popen "rpm -q --requires #{rpm_name}" do |f2|
      while line2 = f2.gets do
        if line2 =~ /Qt/
          return true
        end
      end
    end
    false
  end

  def is_library? rpm_name
    rpm_name =~ /^lib/
  end

  def is_32bit? rpm_name
    rpm_name =~ /\-32bit/
  end

  def cut_off_number_suffix name
    if @cut_off_exceptions.include? name
      return name
    end

    i = name.length - 1
    while i > 0
      if name[i].chr !~ /[\-_0-9]/
        break
      end
      i -= 1
    end
    if i > 0
      return name[0..i]
    end
    name
  end

  def process_all_rpms
    if !File.exist? @settings.cache_dir + "/qt_source.json"
      create_qt_source_cache
    end
    
    qt_sources = Hash.new
    File.open @settings.cache_dir + "/qt_source.json" do |file|
      qt_sources = JSON file.read
    end

    qt_sources.each do |source,sections|
      sections["all"].each do |rpm|
        if rpm =~ /(.*)-devel$/
          name = $1

          if name =~ /^lib(.*)/
            name = $1
          end

          lib_rpm = ""
          sections["lib"].each do |lib|
            if lib !~ /\-devel$/
              lib_rpm = lib
              break
            end
          end
          if lib_rpm.empty?
            lib_rpm = rpm
          end
        
          puts "Identified manifest: #{name} (Library RPM: #{lib_rpm})"
        
          if !dry_run
            create_manifest name, lib_rpm
          end
        end
      end
    end
  end

  def read_source_cache
    if !File.exist? @settings.cache_dir + "/source.json"
      create_source_cache
    end
  
    sources = Hash.new
    File.open @settings.cache_dir + "/source.json" do |file|
      sources = JSON file.read
    end

    sources
  end

  def create_source_cache
    puts "Creating cache of RPM meta data"
    get_involved "Create more friendly progress display for cache creation"
    sources = Hash.new
    IO.popen "rpmqpack" do |f|
      while line = f.gets do
        rpm_name = line.chomp
        puts "SCAN #{rpm_name}"
        source_rpm = `rpm -q --queryformat '%{SOURCERPM}' #{rpm_name}`
        sources[rpm_name] = source_rpm
      end
    end

    File.open @settings.cache_dir + "/source.json", "w" do |f|
      f.puts sources.to_json
    end
  end

  def create_qt_source_cache
    puts "Creating cache of Qt library RPMs"

    sources = read_source_cache

    rpms = Hash.new    
    sources.each do |rpm,source|
      if rpms.has_key? source
        rpms[source] = rpms[source].push rpm
      else
        rpms[source] = Array.new.push rpm
      end
    end

    qt_sources = Hash.new
    sources.each do |rpm,source|
      next unless requires_qt? rpm
      next unless is_library? rpm
      next if is_32bit? rpm

      if !qt_sources.has_key? source
        sections = Hash.new
        sections[:all] = Array.new
        sections[:lib] = Array.new
        qt_sources[source] = sections
      end
      
      qt_sources[source][:all] = rpms[source]
      qt_sources[source][:lib] = qt_sources[source][:lib].push rpm

      puts "Found RPM #{rpm} (#{source})"
    end
  
    File.open @settings.cache_dir + "/qt_source.json", "w" do |f|
      f.puts JSON.pretty_generate qt_sources
    end
  end

end